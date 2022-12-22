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
    pkey = OpenSSL::PKey.generate_parameters("EC", {
      "ec_paramgen_curve" => "secp384r1",
    })
    assert_instance_of OpenSSL::PKey::EC, pkey
    assert_equal "secp384r1", pkey.group.curve_name
    assert_equal nil, pkey.private_key

    # Invalid options are checked
    assert_raise(OpenSSL::PKey::PKeyError) {
      OpenSSL::PKey.generate_parameters("EC", "invalid" => "option")
    }

    # Parameter generation callback is called
    cb_called = []
    assert_raise(RuntimeError) {
      OpenSSL::PKey.generate_parameters("DSA") { |*args|
        cb_called << args
        raise "exit!" if cb_called.size == 3
      }
    }
    if !cb_called && openssl?(3, 0, 0) && !openssl?(3, 0, 6)
      # Errors in BN_GENCB were not properly handled. This special pend is to
      # suppress failures on Ubuntu 22.04, which uses OpenSSL 3.0.2.
      pend "unstable test on OpenSSL 3.0.[0-5]"
    end
    assert_not_empty cb_called
  end

  def test_s_generate_key
    assert_raise(OpenSSL::PKey::PKeyError) {
      # DSA key pair cannot be generated without parameters
      OpenSSL::PKey.generate_key("DSA")
    }
    pkey_params = OpenSSL::PKey.generate_parameters("EC", {
      "ec_paramgen_curve" => "secp384r1",
    })
    pkey = OpenSSL::PKey.generate_key(pkey_params)
    assert_instance_of OpenSSL::PKey::EC, pkey
    assert_equal "secp384r1", pkey.group.curve_name
    assert_not_equal nil, pkey.private_key
  end

  def test_hmac_sign_verify
    pkey = OpenSSL::PKey.generate_key("HMAC", { "key" => "abcd" })

    hmac = OpenSSL::HMAC.new("abcd", "SHA256").update("data").digest
    assert_equal hmac, pkey.sign("SHA256", "data")

    # EVP_PKEY_HMAC does not support verify
    assert_raise(OpenSSL::PKey::PKeyError) {
      pkey.verify("SHA256", "data", hmac)
    }
  end

  def test_ed25519
    # Test vector from RFC 8032 Section 7.1 TEST 2
    priv_pem = <<~EOF
    -----BEGIN PRIVATE KEY-----
    MC4CAQAwBQYDK2VwBCIEIEzNCJso/5banbbDRuwRTg9bijGfNaumJNqM9u1PuKb7
    -----END PRIVATE KEY-----
    EOF
    pub_pem = <<~EOF
    -----BEGIN PUBLIC KEY-----
    MCowBQYDK2VwAyEAPUAXw+hDiVqStwqnTRt+vJyYLM8uxJaMwM1V8Sr0Zgw=
    -----END PUBLIC KEY-----
    EOF
    begin
      priv = OpenSSL::PKey.read(priv_pem)
      pub = OpenSSL::PKey.read(pub_pem)
    rescue OpenSSL::PKey::PKeyError
      # OpenSSL < 1.1.1
      pend "Ed25519 is not implemented"
    end
    assert_instance_of OpenSSL::PKey::PKey, priv
    assert_instance_of OpenSSL::PKey::PKey, pub
    assert_equal priv_pem, priv.private_to_pem
    assert_equal pub_pem, priv.public_to_pem
    assert_equal pub_pem, pub.public_to_pem

    sig = [<<~EOF.gsub(/[^0-9a-f]/, "")].pack("H*")
    92a009a9f0d4cab8720e820b5f642540
    a2b27b5416503f8fb3762223ebdb69da
    085ac1e43e15996e458f3613d0f11d8c
    387b2eaeb4302aeeb00d291612bb0c00
    EOF
    data = ["72"].pack("H*")
    assert_equal sig, priv.sign(nil, data)
    assert_equal true, priv.verify(nil, sig, data)
    assert_equal true, pub.verify(nil, sig, data)
    assert_equal false, pub.verify(nil, sig, data.succ)

    # PureEdDSA wants nil as the message digest
    assert_raise(OpenSSL::PKey::PKeyError) { priv.sign("SHA512", data) }
    assert_raise(OpenSSL::PKey::PKeyError) { pub.verify("SHA512", sig, data) }

    # Ed25519 pkey type does not support key derivation
    assert_raise(OpenSSL::PKey::PKeyError) { priv.derive(pub) }
  end

  def test_x25519
    # Test vector from RFC 7748 Section 6.1
    alice_pem = <<~EOF
    -----BEGIN PRIVATE KEY-----
    MC4CAQAwBQYDK2VuBCIEIHcHbQpzGKV9PBbBclGyZkXfTC+H68CZKrF3+6UduSwq
    -----END PRIVATE KEY-----
    EOF
    bob_pem = <<~EOF
    -----BEGIN PUBLIC KEY-----
    MCowBQYDK2VuAyEA3p7bfXt9wbTTW2HC7OQ1Nz+DQ8hbeGdNrfx+FG+IK08=
    -----END PUBLIC KEY-----
    EOF
    shared_secret = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"
    begin
      alice = OpenSSL::PKey.read(alice_pem)
      bob = OpenSSL::PKey.read(bob_pem)
    rescue OpenSSL::PKey::PKeyError
      # OpenSSL < 1.1.0
      pend "X25519 is not implemented"
    end
    assert_instance_of OpenSSL::PKey::PKey, alice
    assert_equal alice_pem, alice.private_to_pem
    assert_equal bob_pem, bob.public_to_pem
    assert_equal [shared_secret].pack("H*"), alice.derive(bob)
  end

  def test_compare?
    key1 = Fixtures.pkey("rsa1024")
    key2 = Fixtures.pkey("rsa1024")
    key3 = Fixtures.pkey("rsa2048")
    key4 = Fixtures.pkey("dh-1")

    assert_equal(true, key1.compare?(key2))
    assert_equal(true, key1.public_key.compare?(key2))
    assert_equal(true, key2.compare?(key1))
    assert_equal(true, key2.public_key.compare?(key1))

    assert_equal(false, key1.compare?(key3))

    assert_raise(TypeError) do
      key1.compare?(key4)
    end
  end

  def test_to_text
    rsa = Fixtures.pkey("rsa1024")
    assert_include rsa.to_text, "publicExponent"
  end
end
