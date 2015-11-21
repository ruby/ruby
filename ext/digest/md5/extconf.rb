# -*- coding: us-ascii -*-
# $RoughId: extconf.rb,v 1.3 2001/08/14 19:54:51 knu Exp $
# $Id$

require "mkmf"
require File.expand_path("../../digest_conf", __FILE__)

$defs << "-DHAVE_CONFIG_H"

$objs = [ "md5init.#{$OBJEXT}" ]

digest_conf("md5")

have_header("sys/cdefs.h")

$preload = %w[digest]

create_makefile("digest/md5")
