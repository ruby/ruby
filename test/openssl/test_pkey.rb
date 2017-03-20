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

  def test_s_generate_parameters
    # 512 is non-default; 1024 is used if 'dsa_paramgen_bits' is not specified
    # with OpenSSL 1.1.0.
    pkey = OpenSSL::PKey.generate_parameters("DSA", {
      "dsa_paramgen_bits" => 512,
      "dsa_paramgen_q_bits" => 256,
    })
    assert_instance_of OpenSSL::PKey::DSA, pkey
    assert_equal 512, pkey.p.num_bits
    assert_equal 256, pkey.q.num_bits
    assert_equal nil, pkey.priv_key

    # Invalid options are checked
    assert_raise(OpenSSL::PKey::PKeyError) {
      OpenSSL::PKey.generate_parameters("DSA", "invalid" => "option")
    }

    # Parameter generation callback is called
    cb_called = []
    assert_raise(RuntimeError) {
      OpenSSL::PKey.generate_parameters("DSA") { |*args|
        cb_called << args
        raise "exit!" if cb_called.size == 3
      }
    }
    assert_not_empty cb_called
  end

  def test_s_generate_key
    assert_raise(OpenSSL::PKey::PKeyError) {
      # DSA key pair cannot be generated without parameters
      OpenSSL::PKey.generate_key("DSA")
    }
    pkey_params = OpenSSL::PKey.generate_parameters("DSA", {
      "dsa_paramgen_bits" => 512,
      "dsa_paramgen_q_bits" => 256,
    })
    pkey = OpenSSL::PKey.generate_key(pkey_params)
    assert_instance_of OpenSSL::PKey::DSA, pkey
    assert_equal 512, pkey.p.num_bits
    assert_not_equal nil, pkey.priv_key
  end
end
