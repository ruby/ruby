# frozen_string_literal: false
#--
# = Ruby-space predefined Digest subclasses
#
# = Info
# 'OpenSSL for Ruby 2' project
# Copyright (C) 2002  Michal Rokos <m.rokos@sh.cvut.cz>
# All rights reserved.
#
# = Licence
# This program is licensed under the same licence as Ruby.
# (See the file 'LICENCE'.)
#++

module OpenSSL
  class Digest

    alg = %w(DSS DSS1 MD2 MD4 MD5 MDC2 RIPEMD160 SHA SHA1)
    if OPENSSL_VERSION_NUMBER > 0x00908000
      alg += %w(SHA224 SHA256 SHA384 SHA512)
    end

    # Return the +data+ hash computed with +name+ Digest. +name+ is either the
    # long name or short name of a supported digest algorithm.
    #
    # === Examples
    #
    #   OpenSSL::Digest.digest("SHA256", "abc")
    #
    # which is equivalent to:
    #
    #   OpenSSL::Digest::SHA256.digest("abc")

    def self.digest(name, data)
      super(data, name)
    end

    alg.each{|name|
      klass = Class.new(self) {
        define_method(:initialize, ->(data = nil) {super(name, data)})
      }
      singleton = (class << klass; self; end)
      singleton.class_eval{
        define_method(:digest){|data| new.digest(data) }
        define_method(:hexdigest){|data| new.hexdigest(data) }
      }
      const_set(name, klass)
    }

    # Deprecated.
    #
    # This class is only provided for backwards compatibility.
    class Digest < Digest # :nodoc:
      # Deprecated.
      #
      # See OpenSSL::Digest.new
      def initialize(*args)
        warn('Digest::Digest is deprecated; use Digest')
        super(*args)
      end
    end

  end # Digest

  # Returns a Digest subclass by +name+.
  #
  #   require 'openssl'
  #
  #   OpenSSL::Digest("MD5")
  #   # => OpenSSL::Digest::MD5
  #
  #   Digest("Foo")
  #   # => NameError: wrong constant name Foo

  def Digest(name)
    OpenSSL::Digest.const_get(name)
  end

  module_function :Digest

end # OpenSSL
