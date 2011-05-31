begin
  require "openssl"
  require File.join(File.dirname(__FILE__), "utils.rb")
rescue LoadError
end
require 'test/unit'

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

  def test_new
    key = OpenSSL::PKey::RSA.new 512
    pem  = key.public_key.to_pem
    OpenSSL::PKey::RSA.new pem
    assert_equal([], OpenSSL.errors)
  end

  def test_sign_verify
    key = OpenSSL::PKey::RSA.new(512)
    digest = OpenSSL::Digest::SHA1.new
    data = 'Sign me!'
    sig = key.sign(digest, data)
    assert(key.verify(digest, sig, data))
  end

  def test_digest_state_irrelevant_sign
    key = OpenSSL::PKey::RSA.new(512)
    digest1 = OpenSSL::Digest::SHA1.new
    digest2 = OpenSSL::Digest::SHA1.new
    data = 'Sign me!'
    digest1 << 'Change state of digest1'
    sig1 = key.sign(digest1, data)
    sig2 = key.sign(digest2, data)
    assert_equal(sig1, sig2)
  end

  def test_digest_state_irrelevant_verify
    key = OpenSSL::PKey::RSA.new(512)
    digest1 = OpenSSL::Digest::SHA1.new
    digest2 = OpenSSL::Digest::SHA1.new
    data = 'Sign me!'
    sig = key.sign(digest1, data)
    digest1.reset
    digest1 << 'Change state of digest1'
    assert(key.verify(digest1, sig, data))
    assert(key.verify(digest2, sig, data))
  end
end
end
