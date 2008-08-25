#!/usr/bin/env ruby
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'digest/sha1'

module Gem
  if RUBY_VERSION >= '1.8.6'
    SHA1 = Digest::SHA1
  else
    require 'rubygems/digest/digest_adapter'
    SHA1 = DigestAdapter.new(Digest::SHA1)
  end
end