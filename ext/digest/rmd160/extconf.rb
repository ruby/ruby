# $RoughId: extconf.rb,v 1.3 2001/08/14 19:54:51 knu Exp $
# $Id$

require "mkmf"

$CFLAGS << " -DHAVE_CONFIG_H -I#{File.dirname(__FILE__)}/.."

$objs = [ "rmd160init.#{$OBJEXT}" ]

dir_config("openssl")

if !with_config("bundled-rmd160") &&
    have_library("crypto") && have_header("openssl/ripemd.h")
  $objs << "rmd160ossl.#{$OBJEXT}"
  $libs << " -lcrypto"
else
  $objs << "rmd160.#{$OBJEXT}" << "rmd160hl.#{$OBJEXT}"
end

have_header("sys/cdefs.h")

have_header("inttypes.h")

have_header("unistd.h")

$preload = %w[digest]

create_makefile("digest/rmd160")
