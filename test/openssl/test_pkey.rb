# frozen_string_literal: true
require_relative "utils"

class OpenSSL::TestPKey < OpenSSL::PKeyTestCase
  def test_generic_oid_inspect
    # RSA private key
    rsa = Fixtures.pkey("rsa-1")
    assert_instance_of OpenSSL::PKey::RSA, rsa
    assert_equal "rsaEncryption", rsa.oid
    assert_match %r{oid=rsaEncryption}, rsa.inspect

    # X25519 private key
    x25519_pem = <<~EOF
    -----BEGIN PRIVATE KEY-----
    MC4CAQAwBQYDK2VuBCIEIHcHbQpzGKV9PBbBclGyZkXfTC+H68CZKrF3+6UduSwq
    -----END PRIVATE KEY-----
    EOF
    begin
      x25519 = OpenSSL::PKey.read(x25519_pem)
    rescue OpenSSL::PKey::PKeyError
      # OpenSSL < 1.1.0
      pend "X25519 is not implemented"
    end
    assert_instance_of OpenSSL::PKey::PKey, x25519
    assert_equal "X25519", x25519.oid
    assert_match %r{oid=X25519}, x25519.inspect
  end
end
