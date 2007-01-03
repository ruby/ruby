=begin
= $RCSfile: cipher.rb,v $ -- Ruby-space predefined Cipher subclasses

= Info
  'OpenSSL for Ruby 2' project
  Copyright (C) 2002  Michal Rokos <m.rokos@sh.cvut.cz>
  All rights reserved.

= Licence
  This program is licenced under the same licence as Ruby.
  (See the file 'LICENCE'.)

= Version
  $Id$
=end

##
# Should we care what if somebody require this file directly?
#require 'openssl'

module OpenSSL
  module Cipher
    %w(AES CAST5 BF DES IDEA RC2 RC4 RC5).each{|name|
      klass = Class.new(Cipher){
        define_method(:initialize){|*args|
          cipher_name = args.inject(name){|n, arg| "#{n}-#{arg}" }
          super(cipher_name)
        }
      }
      const_set(name, klass)
    }

    %w(128 192 256).each{|keylen|
      klass = Class.new(Cipher){
        define_method(:initialize){|mode|
          mode ||= "CBC"
          cipher_name = "AES-#{keylen}-#{mode}"
          super(cipher_name)
        }
      }
      const_set("AES#{keylen}", klass)
    }

    class Cipher
      def random_key
        str = OpenSSL::Random.random_bytes(self.key_len)
        self.key = str
        return str
      end

      def random_iv
        str = OpenSSL::Random.random_bytes(self.iv_len)
        self.iv = str
        return str
      end
    end
  end # Cipher
end # OpenSSL
