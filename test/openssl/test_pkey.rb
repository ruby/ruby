# frozen_string_literal: false
require_relative "utils"

if defined?(OpenSSL::TestUtils)

class OpenSSL::TestPKey < OpenSSL::PKeyTestCase
  PKEYS = {
    OpenSSL::PKey::RSA => {
      key: OpenSSL::TestUtils::TEST_KEY_RSA1024,
      digest: OpenSSL::Digest::SHA1,
    },
    OpenSSL::PKey::DSA => {
      key: OpenSSL::TestUtils::TEST_KEY_DSA512,
      digest: OpenSSL::TestUtils::DSA_SIGNATURE_DIGEST,
    },
  }
  if defined?(OpenSSL::PKey::EC)
    PKEYS[OpenSSL::PKey::EC] = {
      key: OpenSSL::TestUtils::TEST_KEY_EC_P256V1,
      digest: OpenSSL::Digest::SHA1,
    }
  end

  def test_sign_verify
    data = "Sign me!"
    invalid_data = "Sign me?"
    PKEYS.each do |klass, prop|
      key = prop[:key]
      pub_key = dup_public(prop[:key])
      digest = prop[:digest].new
      signature = key.sign(digest, data)
      assert_equal(true, pub_key.verify(digest, signature, data))
      assert_equal(false, pub_key.verify(digest, signature, invalid_data))
      # digest state is irrelevant
      digest << "unya"
      assert_equal(true, pub_key.verify(digest, signature, data))
      assert_equal(false, pub_key.verify(digest, signature, invalid_data))

      if OpenSSL::OPENSSL_VERSION_NUMBER > 0x10000000
        digest = OpenSSL::Digest::SHA256.new
        signature = key.sign(digest, data)
        assert_equal(true, pub_key.verify(digest, signature, data))
        assert_equal(false, pub_key.verify(digest, signature, invalid_data))
      end
    end
  end
end

end
