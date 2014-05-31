# == License
#
# Copyright (c) 2006 Akinori MUSHA <knu@iDaemons.org>
#
# Documentation by Akinori MUSHA
#
# All rights reserved.  You can redistribute and/or modify it under
# the same terms as Ruby.
#
#   $Id$
#

warn "use of the experimetal library 'digest/hmac' is discouraged; require 'openssl' and use OpenSSL::HMAC instead." if $VERBOSE

require 'digest'

module Digest
  # = digest/hmac.rb
  #
  # An experimental implementation of HMAC keyed-hashing algorithm
  #
  # == Overview
  #
  # CAUTION: Use of this library is discouraged, because this
  # implementation was meant to be experimental but somehow got into the
  # 1.9 series without being noticed.  Please use OpenSSL::HMAC in the
  # "openssl" library instead.
  #
  # == Examples
  #
  #   require 'digest/hmac'
  #
  #   # one-liner example
  #   puts Digest::HMAC.hexdigest("data", "hash key", Digest::SHA1)
  #
  #   # rather longer one
  #   hmac = Digest::HMAC.new("foo", Digest::RMD160)
  #
  #   buf = ""
  #   while stream.read(16384, buf)
  #     hmac.update(buf)
  #   end
  #
  #   puts hmac.hexdigest
  #
  class HMAC < Digest::Class

    # Creates a Digest::HMAC instance.

    def initialize(key, digester)
      @md = digester.new

      block_len = @md.block_length

      if key.bytesize > block_len
        key = @md.digest(key)
      end

      ipad = Array.new(block_len, 0x36)
      opad = Array.new(block_len, 0x5c)

      key.bytes.each_with_index { |c, i|
        ipad[i] ^= c
        opad[i] ^= c
      }

      @key = key.freeze
      @ipad = ipad.pack('C*').freeze
      @opad = opad.pack('C*').freeze
      @md.update(@ipad)
    end

    def initialize_copy(other) # :nodoc:
      @md = other.instance_eval { @md.clone }
    end

    # call-seq:
    #   hmac.update(string) -> hmac
    #   hmac << string -> hmac
    #
    # Updates the hmac using a given +string+ and returns self.
    def update(text)
      @md.update(text)
      self
    end
    alias << update

    # call-seq:
    #   hmac.reset -> hmac
    #
    # Resets the hmac to the initial state and returns self.
    def reset
      @md.reset
      @md.update(@ipad)
      self
    end

    def finish # :nodoc:
      d = @md.digest!
      @md.update(@opad)
      @md.update(d)
      @md.digest!
    end
    private :finish

    # call-seq:
    #   hmac.digest_length -> Integer
    #
    # Returns the length in bytes of the hash value of the digest.
    def digest_length
      @md.digest_length
    end

    # call-seq:
    #   hmac.block_length -> Integer
    #
    # Returns the block length in bytes of the hmac.
    def block_length
      @md.block_length
    end

    # call-seq:
    #   hmac.inspect -> string
    #
    # Creates a printable version of the hmac object.
    def inspect
      sprintf('#<%s: key=%s, digest=%s>', self.class.name, @key.inspect, @md.inspect.sub(/^\#<(.*)>$/) { $1 });
    end
  end
end
