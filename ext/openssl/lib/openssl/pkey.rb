# frozen_string_literal: true
#--
# Ruby/OpenSSL Project
# Copyright (C) 2017 Ruby/OpenSSL Project Authors
#++

require_relative 'marshal'

module OpenSSL::PKey
  class DH
    include OpenSSL::Marshal

    # :call-seq:
    #    dh.compute_key(pub_bn) -> string
    #
    # Returns a String containing a shared secret computed from the other
    # party's public value.
    #
    # This method is provided for backwards compatibility, and calls #derive
    # internally.
    #
    # === Parameters
    # * _pub_bn_ is a OpenSSL::BN, *not* the DH instance returned by
    #   DH#public_key as that contains the DH parameters only.
    def compute_key(pub_bn)
      peer = dup
      peer.set_key(pub_bn, nil)
      derive(peer)
    end

    # :call-seq:
    #    dh.generate_key! -> self
    #
    # Generates a private and public key unless a private key already exists.
    # If this DH instance was generated from public \DH parameters (e.g. by
    # encoding the result of DH#public_key), then this method needs to be
    # called first in order to generate the per-session keys before performing
    # the actual key exchange.
    #
    # See also OpenSSL::PKey.generate_key.
    #
    # Example:
    #   dh = OpenSSL::PKey::DH.new(2048)
    #   public_key = dh.public_key #contains no private/public key yet
    #   public_key.generate_key!
    #   puts public_key.private? # => true
    def generate_key!
      unless priv_key
        tmp = OpenSSL::PKey.generate_key(self)
        set_key(tmp.pub_key, tmp.priv_key)
      end
      self
    end

    class << self
      # :call-seq:
      #    DH.generate(size, generator = 2) -> dh
      #
      # Creates a new DH instance from scratch by generating random parameters
      # and a key pair.
      #
      # See also OpenSSL::PKey.generate_parameters and
      # OpenSSL::PKey.generate_key.
      #
      # +size+::
      #   The desired key size in bits.
      # +generator+::
      #   The generator.
      def generate(size, generator = 2, &blk)
        dhparams = OpenSSL::PKey.generate_parameters("DH", {
          "dh_paramgen_prime_len" => size,
          "dh_paramgen_generator" => generator,
        }, &blk)
        OpenSSL::PKey.generate_key(dhparams)
      end

      # Handle DH.new(size, generator) form here; new(str) and new() forms
      # are handled by #initialize
      def new(*args, &blk) # :nodoc:
        if args[0].is_a?(Integer)
          generate(*args, &blk)
        else
          super
        end
      end
    end
  end

  class DSA
    include OpenSSL::Marshal

    class << self
      # :call-seq:
      #    DSA.generate(size) -> dsa
      #
      # Creates a new DSA instance by generating a private/public key pair
      # from scratch.
      #
      # See also OpenSSL::PKey.generate_parameters and
      # OpenSSL::PKey.generate_key.
      #
      # +size+::
      #   The desired key size in bits.
      def generate(size, &blk)
        dsaparams = OpenSSL::PKey.generate_parameters("DSA", {
          "dsa_paramgen_bits" => size,
        }, &blk)
        OpenSSL::PKey.generate_key(dsaparams)
      end

      # Handle DSA.new(size) form here; new(str) and new() forms
      # are handled by #initialize
      def new(*args, &blk) # :nodoc:
        if args[0].is_a?(Integer)
          generate(*args, &blk)
        else
          super
        end
      end
    end
  end

  if defined?(EC)
  class EC
    include OpenSSL::Marshal

    # :call-seq:
    #    ec.dh_compute_key(pubkey) -> string
    #
    # Derives a shared secret by ECDH. _pubkey_ must be an instance of
    # OpenSSL::PKey::EC::Point and must belong to the same group.
    #
    # This method is provided for backwards compatibility, and calls #derive
    # internally.
    def dh_compute_key(pubkey)
      peer = OpenSSL::PKey::EC.new(group)
      peer.public_key = pubkey
      derive(peer)
    end
  end

  class EC::Point
    # :call-seq:
    #    point.to_bn([conversion_form]) -> OpenSSL::BN
    #
    # Returns the octet string representation of the EC point as an instance of
    # OpenSSL::BN.
    #
    # If _conversion_form_ is not given, the _point_conversion_form_ attribute
    # set to the group is used.
    #
    # See #to_octet_string for more information.
    def to_bn(conversion_form = group.point_conversion_form)
      OpenSSL::BN.new(to_octet_string(conversion_form), 2)
    end
  end
  end

  class RSA
    include OpenSSL::Marshal

    class << self
      # :call-seq:
      #    RSA.generate(size, exponent = 65537) -> RSA
      #
      # Generates an \RSA keypair.
      #
      # See also OpenSSL::PKey.generate_key.
      #
      # +size+::
      #   The desired key size in bits.
      # +exponent+::
      #   An odd Integer, normally 3, 17, or 65537.
      def generate(size, exp = 0x10001, &blk)
        OpenSSL::PKey.generate_key("RSA", {
          "rsa_keygen_bits" => size,
          "rsa_keygen_pubexp" => exp,
        }, &blk)
      end

      # Handle RSA.new(size, exponent) form here; new(str) and new() forms
      # are handled by #initialize
      def new(*args, &blk) # :nodoc:
        if args[0].is_a?(Integer)
          generate(*args, &blk)
        else
          super
        end
      end
    end
  end
end
