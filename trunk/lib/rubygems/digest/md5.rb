#!/usr/bin/env ruby
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'digest/md5'

# :stopdoc:
module Gem
  if RUBY_VERSION >= '1.8.6'
    MD5 = Digest::MD5
  else
    require 'rubygems/digest/digest_adapter'
    MD5 = DigestAdapter.new(Digest::MD5)
    def MD5.md5(string)
      self.hexdigest(string)
    end
  end
end
# :startdoc:

