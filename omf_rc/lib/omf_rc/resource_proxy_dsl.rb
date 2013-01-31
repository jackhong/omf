# DSL contains some helper methods to ease the process defining resource proxies
#
module OmfRc::ResourceProxyDSL
  PROXY_DIR = "omf_rc/resource_proxy"
  UTIL_DIR = "omf_rc/util"

  DEF_ACCESS = [:configure, :request]

  def self.included(base)
    base.extend(ClassMethods)
  end

  # Methods defined here will be available in resource/utility definition files
  #
  module ClassMethods
    # Register a named proxy entry with factory class, normally this should be done in the proxy module
    #
    # @param [Symbol] name of the resource proxy
    # @param [Hash] opts options to be passed to proxy registration
    # @option opts [String, Array] :create_by resource can only be created by these resources.
    #
    # @example suppose we define a module for wifi
    #
    #   module OmfRc::ResourceProxy::Wifi
    #     include OmfRc::ResourceProxyDSL
    #
    #     # Let the factory know it is available
    #     register_proxy :wifi
    #
    #     # or use option :create_by
    #     register_proxy :wifi, :create_by => :node
    #   end
    #
    def register_proxy(name, opts = {})
      name = name.to_sym
      opts = Hashie::Mash.new(opts)
      if opts[:create_by] && !opts[:create_by].kind_of?(Array)
        opts[:create_by] = [opts[:create_by]]
      end
      opts[:proxy_module] = self
      OmfRc::ResourceFactory.register_proxy(name => opts)
    end

    # Register some hooks which can be called at certain stage of the operation
    #
    # Currently the system supports these hooks:
    #
    # * before_ready, called when a resource created, before creating an associated pubsub topic
    # * before_release, called before a resource released
    # * before_create, called before parent creates the child resource. (in the context of parent resource)
    # * after_create, called after parent creates the child resource.
    # * after_initial_configured, called after child resource created, and initial set of properties have been configured.
    #
    # The sequence of execution is:
    # * before_create
    # * before_ready
    # * after_create
    # * after_initial_configured
    # * before_release
    #
    # @param [Symbol] name hook name. :before_create or :before_release
    # @yieldparam [AbstractResource] resource pass the current resource object to the block
    # @example
    #
    #   module OmfRc::ResourceProxy::Node
    #    include OmfRc::ResourceProxyDSL
    #
    #    register_proxy :node
    #
    #    # before_create hook
    #    #
    #    # the optional block will have access to three variables:
    #    # * resource: the parent resource itself
    #    # * new_resource_type: a string or symbol represents the new resource to be created
    #    # * new_resource_options: the options hash to be passed to the new resource
    #    #
    #    # this hook enable us to do things like:
    #    # * validating child resources: e.g. if parent could create this new resource
    #    # * setting up default child properties based on parent's property value
    #    hook :before_create do |resource, new_resource_type, new_resource_options|
    #      if new_resource_type.to_sym == :wifi
    #        logger.info "Resource type wifi is allowed"
    #      else
    #        raise "Go away, I can't create #{new_resource_type}"
    #      end
    #      new_resource_options.property ||= Hashie::Mash.new
    #      new_resource_options.property.node_info = "Node #{resource.uid}"
    #    end
    #
    #    # after_create hook
    #    #
    #    # the optional block will have access to these variables:
    #    # * resource: the parent resource itself
    #    # * new_resource: the child resource instance
    #    hook :after_create do |resource, new_resource|
    #      logger.info "#{resource.uid} created #{new_resource.uid}
    #    end
    #
    #    # before_ready hook
    #    #
    #    # the optional block will have access to resource instance. Useful to initialise resource
    #    hook :before_ready do |resource|
    #      logger.info "#{resource.uid} is now ready"
    #    end
    #
    #    # before_release hook
    #    #
    #    # the optional block will have access to resource instance. Useful to clean up resource before release it.
    #    hook :before_release do |resource|
    #      logger.info "#{resource.uid} is now released"
    #    end
    #
    #    # after_initial_configured hook
    #    #
    #    # the optional block will have access to resource instance. Useful for actions depends on certain configured property values.
    #    hook :after_initial_configured do |resource|
    #      logger.info "#{resource.uid} has an IP address" unless resource.request_ip_addr.nil?
    #    end
    #   end
    def hook(name, &register_block)
      define_method(name) do |*args, &block|
        register_block.call(self, *args, block) if register_block
      end
    end

    # Include the utility by providing a name
    #
    # The utility file can be added to the default utility directory UTIL_DIR, or defined inline.
    #
    # @param [Symbol] name of the utility
    # @example assume we have a module called iw.rb in the omf_rc/util directory, providing a module named OmfRc::Util::Iw with functionalities based on iw cli
    #
    #   module OmfRc::ResourceProxy::Wifi
    #     include OmfRc::ResourceProxyDSL
    #
    #     # Simply include this util module
    #     utility :iw
    #   end
    def utility(name)
      name = name.to_s
      begin
        # In case of module defined inline
        include "OmfRc::Util::#{name.camelize}".constantize
        extend "OmfRc::Util::#{name.camelize}".constantize
      rescue NameError
        begin
          # Then we try to require the file and include the module
          require "#{UTIL_DIR}/#{name}"
          include "OmfRc::Util::#{name.camelize}".constantize
          extend "OmfRc::Util::#{name.camelize}".constantize
        rescue LoadError => le
          logger.error le.message
        rescue NameError => ne
          logger.error ne.message
        end
      end
    end

    # Register a configurable property
    #
    # Please note that the result of the last line in the configure block will be returned via 'inform' message.
    # If you want to make sure that user get a proper notification about the configure operation, simply use the last line to return such notification
    #
    # @param [Symbol] name of the property
    # @yieldparam [AbstractResource] resource pass the current resource object to the block
    # @yieldparam [Object] value pass the value to be configured
    # @example suppose we define a utility for iw command interaction
    #
    #   module OmfRc::Util::Iw
    #     include OmfRc::ResourceProxyDSL
    #
    #     configure :freq do |resource, value|
    #       `iw #{resource.hrn} set freq #{value}`
    #       "Frequency set to #{value}"
    #     end
    #
    #     # or use iterator to define multiple properties
    #     %w(freq channel type).each do |p|
    #       configure p do |resource, value|
    #         `iw #{resource.hrn} set freq #{value}`
    #       end
    #     end
    #
    #     # or we can try to parse iw's help page to extract valid properties and then automatically register them
    #     `iw help`.chomp.gsub(/^\t/, '').split("\n").map {|v| v.match(/[phy|dev] <.+> set (\w+) .*/) && $1 }.compact.uniq.each do |p|
    #       configure p do |resource, value|
    #         `iw #{resource.hrn} set #{p} #{value}`
    #       end
    #     end
    #   end
    #
    def configure(name, &register_block)
      define_method("configure_#{name.to_s}") do |*args, &block|
        args[0] = Hashie::Mash.new(args[0]) if args[0].class == Hash
        register_block.call(self, *args, block) if register_block
      end
    end

    # Register a property that could be requested
    #
    # @param (see #configure)
    # @yieldparam [AbstractResource] resource pass the current resource object to the block
    # @example suppose we define a utility for iw command interaction
    #   module OmfRc::Util::Iw
    #     include OmfRc::ResourceProxyDSL
    #
    #     request :freq do |resource|
    #       `iw #{resource.hrn} link`.match(/^(freq):\W*(.+)$/) && $2
    #     end
    #
    #     # or we can grab everything from output of iw link command and return as a hash(mash)
    #     `iw #{resource.hrn} link`.chomp.gsub(/^\t/, '').split("\n").drop(1).each do |v|
    #       v.match(/^(.+):\W*(.+)$/).tap do |m|
    #         m && known_properties[m[1].downcase.gsub(/\W+/, '_')] = m[2].gsub(/^\W+/, '')
    #       end
    #     end
    #   end
    def request(name, &register_block)
      define_method("request_#{name.to_s}") do |*args, &block|
        args[0] = Hashie::Mash.new(args[0]) if args[0].class == Hash
        register_block.call(self, *args, block) if register_block
      end
    end

    # Define an arbitrary method to do some work, can be included in configure & request block
    #
    # @param (see #configure)
    # @yieldparam [AbstractResource] resource pass the current resource object to the block
    # @example suppose we define a simple os checking method
    #
    #   work :os do
    #     `uname`
    #   end
    #
    #   # then this os method will be available in all proxy definitions which includes this work method definition.
    #   # if for some reason you need to call 'os' method within the same module, you need to access it via the resource instance.
    #
    #   work :install_software do |resource|
    #     raise 'Can not support non-linux distro yet' if resource.os == 'Linux'
    #   end
    def work(name, &register_block)
      define_method(name) do |*args, &block|
        register_block.call(self, *args, block) if register_block
      end
    end

    # Extend existing hook definition by alias existing method name as "orig_[method_name]"
    #
    # @param [#to_s] hook_name name of existing hook
    # @example extend a hook definition
    #
    #   # suppose existing hook defined as this:
    #   hook :before_ready do |resource|
    #     logger.info "I am ready"
    #   end
    #
    #   # now in a new proxy where we want to extend this hook, add more functionality:
    #
    #   extend_hook :before_ready
    #
    #   hook :before_ready do |resource|
    #     resource.orig_before_ready
    #
    #     logger.info "Now I am really ready"
    #   end
    #
    #   # if we simply want to overwrite the existing hook, just define the same hook without using extend_hook
    #
    #   hook :before_ready do |resource|
    #     logger.info "Not sure if I am ready or not"
    #   end
    #
    def extend_hook(hook_name)
      hook_name = hook_name.to_s
      alias_method "orig_#{hook_name}", hook_name
    end

    # Extend existing work definition by alias existing method name as "orig_[method_name]"
    #
    # @see #extend_hook
    #
    def extend_work(work_name)
      work_name = work_name.to_s
      alias_method "orig_#{work_name}", work_name
    end

    # Extend existing configure definition
    #
    # @param [#to_s] configure_name name of existing configurable property
    #
    # Slightly different to extend_hook, the actual method_name defined by a configure property is "configure_[configurable_property_name]"
    #
    # @example to extend a configurable property
    #
    #   configure :bob do |resource, value|
    #     resource.property.bob = value
    #   end
    #
    #   # To extend this, simply do
    #
    #   extend_configure :bob
    #
    #   configure :bob do |resource, value|
    #     resource.orig_configure_bob(value)
    #     resource.property.bob = "New value: #{value}"
    #   end
    #
    # @see #extend_hook
    #
    def extend_configure(configure_name)
      configure_name = configure_name.to_s
      alias_method "orig_configure_#{configure_name}", "configure_#{configure_name}"
    end

    # Extend existing request definition
    #
    # @see #extend_hook
    # @see #extend_configure
    def extend_request(request_name)
      request_name = request_name.to_s
      alias_method "orig_request_#{request_name}", "request_#{request_name}"
    end

    # Define internal property
    def property(name, opts = {})
      opts = Hashie::Mash.new(opts)

      define_method("def_property_#{name}") do |*args, &block|
        self.property[name] ||= opts[:default]
      end

      access = opts.access || DEF_ACCESS
      access.each do |a|
        case a
        when :configure
          define_method("configure_#{name}") do |val|
            self.property[name] = val
          end

        when :request
          define_method("request_#{name}") do
            self.property[name]
          end

        else
          raise "Unnown access type '#{a}'"
        end
      end
    end
  end
end
