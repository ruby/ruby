# -*- coding: us-ascii -*-
# frozen_string_literal: false
# $RoughId: extconf.rb,v 1.3 2001/08/14 19:54:51 knu Exp $
# $Id$

require "mkmf"
require File.expand_path("../../digest_conf", __FILE__)

$objs = [ "sha1init.#{$OBJEXT}" ]

digest_conf("sha1")

have_header("sys/cdefs.h")

$preload = %w[digest]

create_makefile("digest/sha1")
