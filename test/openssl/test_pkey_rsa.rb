require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestPKeyRSA < Test::Unit::TestCase
  def test_padding
    key = OpenSSL::PKey::RSA.new(512, 3)

    # Need right size for raw mode
    plain0 = "x" * (512/8)
    cipher = key.private_encrypt(plain0, OpenSSL::PKey::RSA::NO_PADDING)
    plain1 = key.public_decrypt(cipher, OpenSSL::PKey::RSA::NO_PADDING)
    assert_equal(plain0, plain1)

    # Need smaller size for pkcs1 mode
    plain0 = "x" * (512/8 - 11)
    cipher1 = key.private_encrypt(plain0, OpenSSL::PKey::RSA::PKCS1_PADDING)
    plain1 = key.public_decrypt(cipher1, OpenSSL::PKey::RSA::PKCS1_PADDING)
    assert_equal(plain0, plain1)

    cipherdef = key.private_encrypt(plain0) # PKCS1_PADDING is default
    plain1 = key.public_decrypt(cipherdef)
    assert_equal(plain0, plain1)
    assert_equal(cipher1, cipherdef)

    # Failure cases
    assert_raise(ArgumentError){ key.private_encrypt() }
    assert_raise(ArgumentError){ key.private_encrypt("hi", 1, nil) }
    assert_raise(OpenSSL::PKey::RSAError){ key.private_encrypt(plain0, 666) }
  end

  def test_private
    key = OpenSSL::PKey::RSA.new(512, 3)
    assert(key.private?)
    key2 = OpenSSL::PKey::RSA.new(key.to_der)
    assert(key2.private?)
    key3 = key.public_key
    assert(!key3.private?)
    key4 = OpenSSL::PKey::RSA.new(key3.to_der)
    assert(!key4.private?)
  end
end

end
