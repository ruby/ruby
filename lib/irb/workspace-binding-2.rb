#
#   bind.rb - 
#   	$Release Version: $
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA(Nihon Rational Software Co.,Ltd)
#
# --
#
#   
#

while true
  IRB::BINDING_QUEUE.push b = binding
end
