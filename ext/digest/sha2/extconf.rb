# $RoughId: extconf.rb,v 1.1 2001/07/13 15:38:27 knu Exp $
# $Id$

require "mkmf"

$CFLAGS << " -DHAVE_CONFIG_H -I.."

$objs = [
  "sha2.#{$OBJEXT}",
  "sha2hl.#{$OBJEXT}",
  "sha2init.#{$OBJEXT}",
]

have_header("sys/cdefs.h")

have_header("inttypes.h")

have_header("unistd.h")

create_makefile("digest/sha2")
