#!/usr/bin/env ruby

require 'omf_rc'
require 'omf_rc/resource_factory'
$stdout.sync = true

options = {
  user: 'alpha',
  password: 'pw',
  server: 'srv.mytestbed.net', # XMPP server domain
  uid: 'mclaren', # Id of the garage (resource)
}

# register_proxy and other dsl methods will try to construct a proxy list
# each proxy list item contains
# :proxy_name, (via register_proxy)
# :create_by, (which resource can create me)
# :property_list (a mash), (via property)
# :request_methods, (via request)
# :configure_methods, (via configure)
#
# if request/configure method missing, resource.method_call will check this item definition hash in this order
# :request_methods, :property_list

module OmfRc::ResourceProxy::Garage
  include OmfRc::ResourceProxyDSL

  register_proxy :garage

  # before_create hook will be called before parent creates the child resource. (in the context of parent resource)
  #
  # the optional block will have access to three variables:
  # * resource: the parent resource itself
  # * new_resource_type: a string or symbol represents the new resource to be created
  # * new_resource_options: the options hash to be passed to the new resource
  #
  # this hook enable us to do things like:
  # * validating child resources: e.g. if parent could create this new resource
  # * setting up default child properties based on parent's property value
  hook :before_create_engine do |garage, engine_opts|
    engine_opts.provider = "#{garage.hrn} #{rand(10)}"

    garage.inform 'STATUS', garage.uid do |message|
      message.property('event', event_type.to_s.upcase)
      message.property('app' , app_id)
      message.property('msg' , "#{msg}")
      message.property('seq' , "#{res.property.event_sequence}")
    end)
  end

  hook :after_create_engine do |garage, engine|
    logger.info "#{garage.hrn} #{engine.hrn}"
  end
end

module OmfRc::ResourceProxy::Engine
  include OmfRc::ResourceProxyDSL

  register_proxy :engine, :create_by => :garage

  property :max_power, :provider, :max_rpm, :rpm, :throttle

  # before_ready hook will be called during the initialisation of the resource instance
  #
  hook :before_ready do |engine|
    # We can now initialise some properties which will be stored in resource's property variable.
    # A set of or request/configure methods for these properties are available automatically, so you don't have to define them again using request/configure DSL method, unless you would like to overwrite the default behaviour.
    engine.max_power ||= 676 # Set the engine maximum power to 676 bhp
    engine.provider ||= 'Honda' # Engine provider defaults to Honda
    engine.max_rpm ||= 12500 # Maximum RPM of the engine is 12,500
    engine.rpm ||= 1000 # After engine starts, RPM will stay at 1000 (i.e. engine is idle)
    engine.throttle ||= 0.0 # Throttle is 0% initially

    # The following simulates the engine RPM, it basically says:
    # * Applying 100% throttle will increase RPM by 5000 per second
    # * Engine will reduce RPM by 250 per second when no throttle applied
    # * If RPM exceed engine's maximum RPM, the engine will blow.
    #
    EM.add_periodic_timer(1) do
      unless engine.rpm == 0
        raise 'Engine blown up' if engine.rpm > engine.max_rpm
        engine.rpm += (engine.throttle * 5000 - 250)
        engine.rpm = 1000 if engine.rpm < 1000
      end
    end
  end

  hook :after_initial_configured do |engine|
    logger.info "New maximum power is now: #{engine.max_power}"
  end

  # before_release hook will be called before the resource is fully released, shut down the engine in this case.
  #
  hook :before_release do |engine|
    # Reduce throttle to 0%
    engine.throttle = 0.0
    # Reduce RPM to 0
    engine.rpm = 0
  end

  # We want RPM to be availabe for requesting
  request :rpm do |engine|
    if engine.rpm > engine.max_rpm
      raise 'Engine blown up'
    else
      engine.rpm.to_i
    end
  end

  request :provider do |engine, args|
    "#{engine.manufacture} - #{args.country}"
  end

  # We want throttle to be availabe for configuring (i.e. changing throttle)
  configure :change_throttle do |engine, value|
    engine.throttle = value.to_f / 100.0
  end

  request :error do |engine|
    raise "You asked for an error, and you got it"
  end
end

EM.run do
  # Use resource factory method to initialise a new instance of garage
  garage = OmfRc::ResourceFactory.new(:garage, options)
  # Let garage connect to XMPP server
  garage.connect

  # Disconnect garage from XMPP server, when these two signals received
  trap(:INT) { garage.disconnect }
  trap(:TERM) { garage.disconnect }
end
