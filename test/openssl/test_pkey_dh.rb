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

  def test_new_break_on_non_fips
    omit_on_fips

    assert_nil(OpenSSL::PKey::DH.new(NEW_KEYLEN) { break })
    assert_raise(RuntimeError) do
      OpenSSL::PKey::DH.new(NEW_KEYLEN) { raise }
    end
  end

  def test_new_break_on_fips
    omit_on_non_fips

    # The block argument is not executed in FIPS case.
    # See https://github.com/ruby/openssl/issues/692 for details.
    assert(OpenSSL::PKey::DH.new(NEW_KEYLEN) { break })
    assert(OpenSSL::PKey::DH.new(NEW_KEYLEN) { raise })
  end

  def test_derive_key
    params = Fixtures.pkey("dh2048_ffdhe2048")
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
    dh = Fixtures.pkey("dh2048_ffdhe2048")
    dh_params = dh.public_key

    asn1 = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Integer(dh.p),
      OpenSSL::ASN1::Integer(dh.g)
    ])
    key = OpenSSL::PKey::DH.new(asn1.to_der)
    assert_same_dh dh_params, key

    pem = <<~EOF
    -----BEGIN DH PARAMETERS-----
    MIIBCAKCAQEA//////////+t+FRYortKmq/cViAnPTzx2LnFg84tNpWp4TZBFGQz
    +8yTnc4kmz75fS/jY2MMddj2gbICrsRhetPfHtXV/WVhJDP1H18GbtCFY2VVPe0a
    87VXE15/V8k1mE8McODmi3fipona8+/och3xWKE2rec1MKzKT0g6eXq8CrGCsyT7
    YdEIqUuyyOP7uWrat2DX9GgdT0Kj3jlN9K5W7edjcrsZCwenyO4KbXCeAvzhzffi
    7MA0BM0oNC9hkXL+nOmFg/+OTxIy7vKBg8P+OxtMb61zO7X8vC7CIAXFjvGDfRaD
    ssbzSibBsu/6iGtCOGEoXJf//////////wIBAg==
    -----END DH PARAMETERS-----
    EOF

    key = OpenSSL::PKey::DH.new(pem)
    assert_same_dh dh_params, key
    key = OpenSSL::PKey.read(pem)
    assert_same_dh dh_params, key

    assert_equal asn1.to_der, dh.to_der
    assert_equal pem, dh.export
  end

  def test_public_key
    dh = Fixtures.pkey("dh2048_ffdhe2048")
    public_key = dh.public_key
    assert_no_key(public_key) #implies public_key.public? is false!
    assert_equal(dh.to_der, public_key.to_der)
    assert_equal(dh.to_pem, public_key.to_pem)
  end

  def test_generate_key
    # Deprecated in v3.0.0; incompatible with OpenSSL 3.0
    # Creates a copy with params only
    dh = Fixtures.pkey("dh2048_ffdhe2048").public_key
    assert_no_key(dh)
    dh.generate_key!
    assert_key(dh)

    dh2 = dh.public_key
    dh2.generate_key!
    assert_equal(dh.compute_key(dh2.pub_key), dh2.compute_key(dh.pub_key))
  end if !openssl?(3, 0, 0)

  def test_params_ok?
    # Skip the tests in old OpenSSL version 1.1.1c or early versions before
    # applying the following commits in OpenSSL 1.1.1d to make `DH_check`
    # function pass the RFC 7919 FFDHE group texts.
    # https://github.com/openssl/openssl/pull/9435
    unless openssl?(1, 1, 1, 4)
      pend 'DH check for RFC 7919 FFDHE group texts is not implemented'
    end

    dh0 = Fixtures.pkey("dh2048_ffdhe2048")

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
    dh1 = Fixtures.pkey("dh2048_ffdhe2048")
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
    dh3 = OpenSSL::PKey.generate_key(Fixtures.pkey("dh2048_ffdhe2048"))
    dh4 = dh3.dup
    assert_equal dh3.to_der, dh4.to_der
    assert_equal dh1.to_der, dh4.to_der # encodes parameters only
    assert_equal [dh1.p, dh1.g], [dh4.p, dh4.g]
    assert_not_equal nil, dh3.pub_key
    assert_not_equal nil, dh3.priv_key
    assert_equal [dh3.pub_key, dh3.priv_key], [dh4.pub_key, dh4.priv_key]
  end

  def test_marshal
    dh = Fixtures.pkey("dh2048_ffdhe2048")
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
