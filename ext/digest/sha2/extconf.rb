# $RoughId: extconf.rb,v 1.1 2001/07/13 15:38:27 knu Exp $
# $Id$

require "mkmf"

$CFLAGS << " -DHAVE_CONFIG_H -I$(srcdir)/.."

$objs = [
  "sha2.#{$OBJEXT}",
  "sha2hl.#{$OBJEXT}",
  "sha2init.#{$OBJEXT}",
]

have_header("sys/cdefs.h")

have_header("inttypes.h")

have_header("unistd.h")

unless try_link(<<SRC, $defs.join(' '))
#include "../defs.h"
main(){}
SRC
  puts "** Cannot find a 64bit integer type - skipping the SHA2 module."
  exit 1
end

create_makefile("digest/sha2")
