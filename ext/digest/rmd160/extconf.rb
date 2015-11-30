# -*- coding: us-ascii -*-
# $RoughId: extconf.rb,v 1.3 2001/08/14 19:54:51 knu Exp $
# $Id$

require "mkmf"

$defs << "-DNDEBUG" << "-DHAVE_CONFIG_H"

$objs = [ "rmd160init.#{$OBJEXT}" ]

dir_config("openssl")
pkg_config("openssl")
require File.expand_path('../../../openssl/deprecation', __FILE__)

if !with_config("bundled-rmd160") &&
    have_library("crypto") && OpenSSL.check_func("RMD160_Transform", "openssl/ripemd.h")
  $objs << "rmd160ossl.#{$OBJEXT}"
else
  $objs << "rmd160.#{$OBJEXT}"
end

have_header("sys/cdefs.h")

$preload = %w[digest]

create_makefile("digest/rmd160")
