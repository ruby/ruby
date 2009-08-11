# $RoughId: extconf.rb,v 1.4 2001/08/14 19:54:51 knu Exp $
# $Id$

require "mkmf"

$defs << "-DHAVE_CONFIG_H"
$INCFLAGS << " -I$(srcdir)/.."

$objs = [
  "sha2.#{$OBJEXT}",
  "sha2init.#{$OBJEXT}",
]

have_header("sys/cdefs.h")

$preload = %w[digest]

if have_type("uint64_t", "defs.h", $defs.join(' '))
  create_makefile("digest/sha2")
end
