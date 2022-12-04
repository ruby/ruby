# frozen_string_literal: true
require_relative 'utils'

if defined?(OpenSSL) && defined?(OpenSSL::PKey::DH)

class OpenSSL::TestPKeyDH < OpenSSL::PKeyTestCase
  NEW_KEYLEN = 2048

  def test_new_empty
    dh = OpenSSL::PKey::DH.new
    assert_equal nil, dh.p
    assert_equal nil, dh.priv_key
  end

  def test_new_generate
    # This test is slow
    dh = OpenSSL::PKey::DH.new(NEW_KEYLEN)
    assert_key(dh)
  end if ENV["OSSL_TEST_ALL"]

  def test_new_break
    assert_nil(OpenSSL::PKey::DH.new(NEW_KEYLEN) { break })
    assert_raise(RuntimeError) do
      OpenSSL::PKey::DH.new(NEW_KEYLEN) { raise }
    end
  end

  def test_derive_key
    params = Fixtures.pkey("dh1024")
    dh1 = OpenSSL::PKey.generate_key(params)
    dh2 = OpenSSL::PKey.generate_key(params)
    dh1_pub = OpenSSL::PKey.read(dh1.public_to_der)
    dh2_pub = OpenSSL::PKey.read(dh2.public_to_der)

    z = dh1.g.mod_exp(dh1.priv_key, dh1.p).mod_exp(dh2.priv_key, dh1.p).to_s(2)
    assert_equal z, dh1.derive(dh2_pub)
    assert_equal z, dh2.derive(dh1_pub)

    assert_raise(OpenSSL::PKey::PKeyError) { params.derive(dh1_pub) }
    assert_raise(OpenSSL::PKey::PKeyError) { dh1_pub.derive(params) }

    assert_equal z, dh1.compute_key(dh2.pub_key)
    assert_equal z, dh2.compute_key(dh1.pub_key)
  end

  def test_DHparams
    dh1024 = Fixtures.pkey("dh1024")
    dh1024params = dh1024.public_key

    asn1 = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Integer(dh1024.p),
      OpenSSL::ASN1::Integer(dh1024.g)
    ])
    key = OpenSSL::PKey::DH.new(asn1.to_der)
    assert_same_dh dh1024params, key

    pem = <<~EOF
    -----BEGIN DH PARAMETERS-----
    MIGHAoGBAKnKQ8MNK6nYZzLrrcuTsLxuiJGXoOO5gT+tljOTbHBuiktdMTITzIY0
    pFxIvjG05D7HoBZQfrR0c92NGWPkAiCkhQKB8JCbPVzwNLDy6DZ0pmofDKrEsYHG
    AQjjxMXhwULlmuR/K+WwlaZPiLIBYalLAZQ7ZbOPeVkJ8ePao0eLAgEC
    -----END DH PARAMETERS-----
    EOF
    key = OpenSSL::PKey::DH.new(pem)
    assert_same_dh dh1024params, key
    key = OpenSSL::PKey.read(pem)
    assert_same_dh dh1024params, key

    assert_equal asn1.to_der, dh1024.to_der
    assert_equal pem, dh1024.export
  end

  def test_public_key
    dh = Fixtures.pkey("dh1024")
    public_key = dh.public_key
    assert_no_key(public_key) #implies public_key.public? is false!
    assert_equal(dh.to_der, public_key.to_der)
    assert_equal(dh.to_pem, public_key.to_pem)
  end

  def test_generate_key
    # Deprecated in v3.0.0; incompatible with OpenSSL 3.0
    dh = Fixtures.pkey("dh1024").public_key # creates a copy with params only
    assert_no_key(dh)
    dh.generate_key!
    assert_key(dh)

    dh2 = dh.public_key
    dh2.generate_key!
    assert_equal(dh.compute_key(dh2.pub_key), dh2.compute_key(dh.pub_key))
  end if !openssl?(3, 0, 0)

  def test_params_ok?
    dh0 = Fixtures.pkey("dh1024")

    dh1 = OpenSSL::PKey::DH.new(OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Integer(dh0.p),
      OpenSSL::ASN1::Integer(dh0.g)
    ]))
    assert_equal(true, dh1.params_ok?)

    dh2 = OpenSSL::PKey::DH.new(OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Integer(dh0.p + 1),
      OpenSSL::ASN1::Integer(dh0.g)
    ]))
    assert_equal(false, dh2.params_ok?)
  end

  def test_dup
    # Parameters only
    dh1 = Fixtures.pkey("dh1024")
    dh2 = dh1.dup
    assert_equal dh1.to_der, dh2.to_der
    assert_not_equal nil, dh1.p
    assert_not_equal nil, dh1.g
    assert_equal [dh1.p, dh1.g], [dh2.p, dh2.g]
    assert_equal nil, dh1.pub_key
    assert_equal nil, dh1.priv_key
    assert_equal [dh1.pub_key, dh1.priv_key], [dh2.pub_key, dh2.priv_key]

    # PKey is immutable in OpenSSL >= 3.0
    if !openssl?(3, 0, 0)
      dh2.set_pqg(dh2.p + 1, nil, dh2.g)
      assert_not_equal dh2.p, dh1.p
    end

    # With a key pair
    dh3 = OpenSSL::PKey.generate_key(Fixtures.pkey("dh1024"))
    dh4 = dh3.dup
    assert_equal dh3.to_der, dh4.to_der
    assert_equal dh1.to_der, dh4.to_der # encodes parameters only
    assert_equal [dh1.p, dh1.g], [dh4.p, dh4.g]
    assert_not_equal nil, dh3.pub_key
    assert_not_equal nil, dh3.priv_key
    assert_equal [dh3.pub_key, dh3.priv_key], [dh4.pub_key, dh4.priv_key]
  end

  def test_marshal
    dh = Fixtures.pkey("dh1024")
    deserialized = Marshal.load(Marshal.dump(dh))

    assert_equal dh.to_der, deserialized.to_der
  end

  private

  def assert_no_key(dh)
    assert_equal(false, dh.public?)
    assert_equal(false, dh.private?)
    assert_equal(nil, dh.pub_key)
    assert_equal(nil, dh.priv_key)
  end

  def assert_key(dh)
    assert(dh.public?)
    assert(dh.private?)
    assert(dh.pub_key)
    assert(dh.priv_key)
  end

  def assert_same_dh(expected, key)
    check_component(expected, key, [:p, :q, :g, :pub_key, :priv_key])
  end
end

end
