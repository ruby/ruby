# $RoughId: extconf.rb,v 1.4 2001/08/14 19:54:51 knu Exp $
# $Id$

require "mkmf"

$CFLAGS << " -DHAVE_CONFIG_H -I#{File.dirname(__FILE__)}/.."

$objs = [
  "sha2.#{$OBJEXT}",
  "sha2hl.#{$OBJEXT}",
  "sha2init.#{$OBJEXT}",
]

have_header("sys/cdefs.h")

have_header("inttypes.h")

have_header("unistd.h")

if try_cpp(<<SRC, $defs.join(' '))
#include "defs.h"
#ifdef NO_UINT64_T
  #error ** Cannot find a 64bit integer type - skipping the SHA2 module.
#endif
SRC
then
  create_makefile("digest/sha2")
end
