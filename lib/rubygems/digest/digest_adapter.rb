#!/usr/bin/env ruby
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

module Gem
  
  # There is an incompatibility between the way Ruby 1.8.5 and 1.8.6 
  # handles digests. This DigestAdapter will take a pre-1.8.6 digest 
  # and adapt it to the 1.8.6 API.
  #
  # Note that only the digest and hexdigest methods are adapted, 
  # since these are the only functions used by Gems.
  #
  class DigestAdapter

    # Initialize a digest adapter.
    def initialize(digest_class)
      @digest_class = digest_class
    end

    # Return a new digester.  Since we are only implementing the stateless
    # methods, we will return ourself as the instance.
    def new
      self
    end

    # Return the digest of +string+ as a hex string.
    def hexdigest(string)
      @digest_class.new(string).hexdigest
    end

    # Return the digest of +string+ as a binary string.
    def digest(string)
      @digest_class.new(string).digest
    end
  end
end