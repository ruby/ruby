# -*- coding: us-ascii -*-
# frozen_string_literal: false
# $RoughId: extconf.rb,v 1.3 2001/08/14 19:54:51 knu Exp $
# $Id$

require "mkmf"
require File.expand_path("../../digest_conf", __FILE__)

$defs << "-DNDEBUG" << "-DHAVE_CONFIG_H"

$objs = [ "rmd160init.#{$OBJEXT}" ]

digest_conf("rmd160")

have_header("sys/cdefs.h")

$preload = %w[digest]

create_makefile("digest/rmd160")
