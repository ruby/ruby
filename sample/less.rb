#! /mp/free/bin/ruby -- -*- ruby -*-
#
#		less - 
#			$Release Version: $
#			$Revision: 1.1 $
#			$Date: 90/09/29 15:17:59 $
#			by Yasuo OHBA(STAFS Development Room)
#
# --
#
#	
#

$RCS_ID="$Header: less,v 1.1 90/09/29 15:17:59 ohba Locked $"

ZCAT = "/usr/local/bin/zcat"
LESS = "/usr/local/bin/less"

FILE = $ARGV.pop
OPTION = (if $ARGV.length == 0; "" else $ARGV.join(" "); end)

if FILE =~ /\.(Z|gz)$/
  exec(format("%s %s | %s %s", ZCAT, FILE, LESS, OPTION))
elsif FILE == nil
  exec(format("%s %s", LESS, OPTION))
else
  print(format("%s %s %s", LESS, OPTION, FILE), "\n")
  exec(format("%s %s %s", LESS, OPTION, FILE))
end
exit()
