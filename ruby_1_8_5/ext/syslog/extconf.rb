# $RoughId: extconf.rb,v 1.3 2001/11/24 17:49:26 knu Exp $
# $Id: extconf.rb,v 1.1 2001/11/26 12:00:40 knu Exp $

require 'mkmf'

have_header("syslog.h") &&
  have_func("openlog") &&
  have_func("setlogmask") &&
  create_makefile("syslog")

