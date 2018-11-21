# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

##
# Classes for building C extensions live here.

module Gem::Ext; end

require 'rubygems/ext/build_error'
require 'rubygems/ext/builder'
require 'rubygems/ext/configure_builder'
require 'rubygems/ext/ext_conf_builder'
require 'rubygems/ext/rake_builder'
require 'rubygems/ext/cmake_builder'
