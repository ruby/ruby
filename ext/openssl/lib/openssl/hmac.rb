# frozen_string_literal: true

module OpenSSL
  class HMAC
    # Securely compare with another HMAC instance in constant time.
    def ==(other)
      return false unless HMAC === other
      return false unless self.digest.bytesize == other.digest.bytesize

      OpenSSL.fixed_length_secure_compare(self.digest, other.digest)
    end
  end
end
