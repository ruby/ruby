# $RoughId: extconf.rb,v 1.3 2001/08/14 19:54:51 knu Exp $
# $Id$

require "mkmf"

$defs << "-DHAVE_CONFIG_H"
$INCFLAGS << " -I$(srcdir)/.."

$objs = [ "md5init.#{$OBJEXT}" ]

dir_config("openssl")
pkg_config("openssl")
require_relative '../../openssl/deprecation'

if !with_config("bundled-md5") &&
    have_library("crypto") && OpenSSL.check_func("MD5_Transform", "openssl/md5.h")
  $objs << "md5ossl.#{$OBJEXT}"

else
  $objs << "md5.#{$OBJEXT}"
end

have_header("sys/cdefs.h")

$preload = %w[digest]

create_makefile("digest/md5")
