# -*- coding: us-ascii -*-
# $RoughId: extconf.rb,v 1.4 2001/08/14 19:54:51 knu Exp $
# $Id$

require "mkmf"

$defs << "-DHAVE_CONFIG_H"
$INCFLAGS << " -I$(srcdir)/.."

$objs = [ "sha2init.#{$OBJEXT}" ]

if !with_config("bundled-sha2") &&
    (dir_config("openssl")
     pkg_config("openssl")
     require File.expand_path('../../../openssl/deprecation', __FILE__)
     have_library("crypto")) &&
    %w[SHA256 SHA512].all? {|d| OpenSSL.check_func("#{d}_Transform", "openssl/sha.h")} &&
    %w[SHA256 SHA512].all? {|d| have_type("#{d}_CTX", "openssl/sha.h")}
  $objs << "sha2ossl.#{$OBJEXT}"
  $defs << "-DSHA2_USE_OPENSSL"
else
  have_type("u_int8_t")
  $objs << "sha2.#{$OBJEXT}"
end

have_header("sys/cdefs.h")

$preload = %w[digest]

if have_type("uint64_t", "defs.h", $defs.join(' '))
  create_makefile("digest/sha2")
end
