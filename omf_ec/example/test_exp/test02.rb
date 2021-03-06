# Copyright (c) 2012 National ICT Australia Limited (NICTA).
# This software may be used and distributed solely under the terms of the MIT license (License).
# You should find a copy of the License in LICENSE.TXT or at http://opensource.org/licenses/MIT.
# By downloading or using this software you accept the terms and the liability disclaimer in the License.

#
# Test 2
#
# Testing 2 nodes in multiple groups running exec commandis for already installed apps
#

defProperty('res1', "node1", "ID of a node")
defProperty('res2', "node2", "ID of a node")

defGroup('Alice', property.res1)
defGroup('Bob', property.res2)
defGroup('Couple', property.res1, property.res2)
defGroup('GroupOfGroup', "Alice", "Bob")

onEvent(:ALL_UP) do
  info "-------------"
  info "TEST - Group of 2 (res1,res2)"
  group("Couple").exec("/bin/hostname")
  info "---------------------"
  info "TEST - Group of Group ( (res1) and (res2) )"
  group("GroupOfGroup").exec("/bin/hostname")
  info "---------------"
  info "TEST - allGroup"
  allGroups.exec("/bin/hostname")

  after(20) { Experiment.done }
end
