#
#   irb/ws-for-case-2.rb - 
#   	$Release Version: 0.7.3$
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#
# --
#
#   
#

while true
  IRB::BINDING_QUEUE.push b = binding
end
