# frozen_string_literal: true
require_relative "utils"

class OpenSSL::TestPKey < OpenSSL::PKeyTestCase
  def test_generic_oid_inspect_rsa
    # RSA private key
    rsa = Fixtures.pkey("rsa-1")
    assert_instance_of OpenSSL::PKey::RSA, rsa
    assert_equal "rsaEncryption", rsa.oid
    assert_match %r{oid=rsaEncryption}, rsa.inspect
    assert_match %r{type_name=RSA}, rsa.inspect if openssl?(3, 0, 0)
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
  end

  def test_s_generate_parameters_with_block
    # DSA kengen is not FIPS-approved.
    # https://github.com/openssl/openssl/commit/49a35f0#diff-605396c063194975af8ce31399d42690ab18186b422fb5012101cc9132660fe1R611-R614
    omit_on_fips

    # Parameter generation callback is called
    if openssl?(3, 0, 0, 0) && !openssl?(3, 0, 0, 6)
      # Errors in BN_GENCB were not properly handled. This special pend is to
      # suppress failures on Ubuntu 22.04, which uses OpenSSL 3.0.2.
      pend "unstable test on OpenSSL 3.0.[0-5]"
    end
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
    # Ed25519 is not FIPS-approved.
    omit_on_fips

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
    priv = OpenSSL::PKey.read(priv_pem)
    pub = OpenSSL::PKey.read(pub_pem)
    assert_instance_of OpenSSL::PKey::PKey, priv
    assert_instance_of OpenSSL::PKey::PKey, pub
    assert_equal priv_pem, priv.private_to_pem
    assert_equal pub_pem, priv.public_to_pem
    assert_equal pub_pem, pub.public_to_pem

    assert_equal "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
      priv.raw_private_key.unpack1("H*")
    assert_equal OpenSSL::PKey.new_raw_private_key("ED25519", priv.raw_private_key).private_to_pem,
      priv.private_to_pem
    assert_equal "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
      priv.raw_public_key.unpack1("H*")
    assert_equal OpenSSL::PKey.new_raw_public_key("ED25519", priv.raw_public_key).public_to_pem,
      pub.public_to_pem

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
    omit_on_fips

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

    alice = OpenSSL::PKey.read(alice_pem)
    bob = OpenSSL::PKey.read(bob_pem)
    assert_instance_of OpenSSL::PKey::PKey, alice
    assert_equal "X25519", alice.oid
    assert_match %r{oid=X25519}, alice.inspect
    assert_equal alice_pem, alice.private_to_pem
    assert_equal bob_pem, bob.public_to_pem
    assert_equal [shared_secret].pack("H*"), alice.derive(bob)

    alice_private = OpenSSL::PKey.new_raw_private_key("X25519", alice.raw_private_key)
    bob_public = OpenSSL::PKey.new_raw_public_key("X25519", bob.raw_public_key)
    assert_equal alice_private.private_to_pem,
      alice.private_to_pem
    assert_equal bob_public.public_to_pem,
      bob.public_to_pem
    assert_equal "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a",
      alice.raw_private_key.unpack1("H*")
    assert_equal "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f",
      bob.raw_public_key.unpack1("H*")
  end

  def test_raw_initialize_errors
    assert_raise(OpenSSL::PKey::PKeyError) { OpenSSL::PKey.new_raw_private_key("foo123", "xxx") }
    assert_raise(OpenSSL::PKey::PKeyError) { OpenSSL::PKey.new_raw_private_key("ED25519", "xxx") }
    assert_raise(OpenSSL::PKey::PKeyError) { OpenSSL::PKey.new_raw_public_key("foo123", "xxx") }
    assert_raise(OpenSSL::PKey::PKeyError) { OpenSSL::PKey.new_raw_public_key("ED25519", "xxx") }
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
