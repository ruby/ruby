#
#   irb/ws-for-case-2.rb - 
#   	$Release Version: 0.9.5$
#   	$Revision: 1.2.2.1 $
#   	$Date: 2005/04/19 19:24:57 $
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#   
#

while true
  IRB::BINDING_QUEUE.push b = binding
end
