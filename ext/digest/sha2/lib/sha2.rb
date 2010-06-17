#--
# sha2.rb - defines Digest::SHA2 class which wraps up the SHA256,
#           SHA384, and SHA512 classes.
#++
# Copyright (c) 2006 Akinori MUSHA <knu@iDaemons.org>
#
# All rights reserved.  You can redistribute and/or modify it under the same
# terms as Ruby.
#
#   $Id$

require 'digest'
begin
  require 'digest/sha2.so'
rescue LoadError
  require 'digest/sha2.bundle'
end

module Digest
  #
  # A meta digest provider class for SHA256, SHA384 and SHA512.
  #
  class SHA2 < Digest::Class
    # call-seq:
    #     Digest::SHA2.new(bitlen = 256) -> digest_obj
    #
    # Creates a new SHA2 hash object with a given bit length.
    def initialize(bitlen = 256)
      case bitlen
      when 256
        @sha2 = Digest::SHA256.new
      when 384
        @sha2 = Digest::SHA384.new
      when 512
        @sha2 = Digest::SHA512.new
      else
        raise ArgumentError, "unsupported bit length: %s" % bitlen.inspect
      end
      @bitlen = bitlen
    end

    # :nodoc:
    def reset
      @sha2.reset
      self
    end

    # :nodoc:
    def update(str)
      @sha2.update(str)
      self
    end
    alias << update

    def finish
      @sha2.digest!
    end
    private :finish

    def block_length
      @sha2.block_length
    end

    def digest_length
      @sha2.digest_length
    end

    # :nodoc:
    def initialize_copy(other)
      @sha2 = other.instance_eval { @sha2.clone }
    end

    # :nodoc:
    def inspect
      "#<%s:%d %s>" % [self.class.name, @bitlen, hexdigest]
    end
  end
end
