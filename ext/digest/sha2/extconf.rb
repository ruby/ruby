# -*- coding: us-ascii -*-
# $RoughId: extconf.rb,v 1.4 2001/08/14 19:54:51 knu Exp $
# $Id$

require "mkmf"
require File.expand_path("../../digest_conf", __FILE__)

$defs << "-DHAVE_CONFIG_H"
$INCFLAGS << " -I$(srcdir)/.."

$objs = [ "sha2init.#{$OBJEXT}" ]

unless digest_conf("sha2", "sha", %w[SHA256 SHA512])
  have_type("u_int8_t")
end

have_header("sys/cdefs.h")

$preload = %w[digest]

if have_type("uint64_t", "defs.h", $defs.join(' '))
  create_makefile("digest/sha2")
end
