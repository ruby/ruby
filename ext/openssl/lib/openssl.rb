# frozen_string_literal: true
=begin
= Info
  'OpenSSL for Ruby 2' project
  Copyright (C) 2002  Michal Rokos <m.rokos@sh.cvut.cz>
  All rights reserved.

= Licence
  This program is licensed under the same licence as Ruby.
  (See the file 'LICENCE'.)
=end

require 'openssl.so'

require_relative 'openssl/bn'
require_relative 'openssl/pkey'
require_relative 'openssl/cipher'
require_relative 'openssl/config'
require_relative 'openssl/digest'
require_relative 'openssl/hmac'
require_relative 'openssl/x509'
require_relative 'openssl/ssl'
require_relative 'openssl/pkcs5'

module OpenSSL
  # call-seq:
  #   OpenSSL.secure_compare(string, string) -> boolean
  #
  # Constant time memory comparison. Inputs are hashed using SHA-256 to mask
  # the length of the secret. Returns +true+ if the strings are identical,
  # +false+ otherwise.
  def self.secure_compare(a, b)
    hashed_a = OpenSSL::Digest::SHA256.digest(a)
    hashed_b = OpenSSL::Digest::SHA256.digest(b)
    OpenSSL.fixed_length_secure_compare(hashed_a, hashed_b) && a == b
  end
end
