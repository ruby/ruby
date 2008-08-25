#!/usr/bin/env ruby
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'digest/sha2'

module Gem
  if RUBY_VERSION >= '1.8.6'
    SHA256 = Digest::SHA256
  else
    require 'rubygems/digest/digest_adapter'
    SHA256 = DigestAdapter.new(Digest::SHA256)
  end
end
