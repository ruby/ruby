require 'mkmf'
$preload = ["tcltklib"]
($INSTALLFILES||=[]) << ["lib/tkextlib/SUPPORT_STATUS", "$(RUBYLIBDIR)", "lib"]
create_makefile("tkutil")
