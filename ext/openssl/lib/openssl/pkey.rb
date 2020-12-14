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
  end

  class DSA
    include OpenSSL::Marshal
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
  end
end
