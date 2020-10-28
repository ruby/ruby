# frozen_string_literal: true
require_relative 'utils'

if defined?(OpenSSL) && defined?(OpenSSL::PKey::DH)

class OpenSSL::TestPKeyDH < OpenSSL::PKeyTestCase
  NEW_KEYLEN = 256

  def test_new
    dh = OpenSSL::PKey::DH.new(NEW_KEYLEN)
    assert_key(dh)
  end

  def test_new_break
    assert_nil(OpenSSL::PKey::DH.new(NEW_KEYLEN) { break })
    assert_raise(RuntimeError) do
      OpenSSL::PKey::DH.new(NEW_KEYLEN) { raise }
    end
  end

  def test_DHparams
    dh1024 = Fixtures.pkey("dh1024")
    asn1 = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Integer(dh1024.p),
      OpenSSL::ASN1::Integer(dh1024.g)
    ])
    key = OpenSSL::PKey::DH.new(asn1.to_der)
    assert_same_dh dup_public(dh1024), key

    pem = <<~EOF
    -----BEGIN DH PARAMETERS-----
    MIGHAoGBAKnKQ8MNK6nYZzLrrcuTsLxuiJGXoOO5gT+tljOTbHBuiktdMTITzIY0
    pFxIvjG05D7HoBZQfrR0c92NGWPkAiCkhQKB8JCbPVzwNLDy6DZ0pmofDKrEsYHG
    AQjjxMXhwULlmuR/K+WwlaZPiLIBYalLAZQ7ZbOPeVkJ8ePao0eLAgEC
    -----END DH PARAMETERS-----
    EOF
    key = OpenSSL::PKey::DH.new(pem)
    assert_same_dh dup_public(dh1024), key

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
    dh = Fixtures.pkey("dh1024").public_key # creates a copy
    assert_no_key(dh)
    dh.generate_key!
    assert_key(dh)
  end

  def test_key_exchange
    dh = Fixtures.pkey("dh1024")
    dh2 = dh.public_key
    dh.generate_key!
    dh2.generate_key!
    assert_equal(dh.compute_key(dh2.pub_key), dh2.compute_key(dh.pub_key))
  end

  def test_dup
    dh = OpenSSL::PKey::DH.new(NEW_KEYLEN)
    dh2 = dh.dup
    assert_equal dh.to_der, dh2.to_der # params
    assert_equal_params dh, dh2 # keys
    dh2.set_pqg(dh2.p + 1, nil, dh2.g)
    assert_not_equal dh2.p, dh.p
    assert_equal dh2.g, dh.g
  end

  def test_marshal
    dh = Fixtures.pkey("dh1024")
    deserialized = Marshal.load(Marshal.dump(dh))

    assert_equal dh.to_der, deserialized.to_der
  end

  private

  def assert_equal_params(dh1, dh2)
    assert_equal(dh1.g, dh2.g)
    assert_equal(dh1.p, dh2.p)
  end

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
