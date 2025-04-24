# -*- coding: us-ascii -*-
# frozen_string_literal: false
# $RoughId: extconf.rb,v 1.3 2001/08/14 19:54:51 knu Exp $
# $Id$

require "mkmf"
require File.expand_path("../../digest_conf", __FILE__)

if try_static_assert("RUBY_API_VERSION_MAJOR < 3", "ruby/version.h")
  $defs << "-DNDEBUG"
end

$objs = [ "crc32init.#{$OBJEXT}" ]

digest_conf("crc32")

have_header("sys/cdefs.h")

$preload = %w[digest]

create_makefile("digest/crc32")
