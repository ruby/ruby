# frozen_string_literal: false
require_relative 'utils'

if defined?(OpenSSL::TestUtils)

class OpenSSL::TestPKeyDH < Test::Unit::TestCase

  NEW_KEYLEN = 256

  def test_DEFAULT_1024
    params = <<-eop
-----BEGIN DH PARAMETERS-----
MIGHAoGBAJ0lOVy0VIr/JebWn0zDwY2h+rqITFOpdNr6ugsgvkDXuucdcChhYExJ
AV/ZD2AWPbrTqV76mGRgJg4EddgT1zG0jq3rnFdMj2XzkBYx3BVvfR0Arnby0RHR
T4h7KZ/2zmjvV+eF8kBUHBJAojUlzxKj4QeO2x20FP9X5xmNUXeDAgEC
-----END DH PARAMETERS-----
    eop
    assert_equal params, OpenSSL::PKey::DH::DEFAULT_1024.to_s
  end

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

  def test_to_der
    dh = OpenSSL::TestUtils::TEST_KEY_DH1024
    der = dh.to_der
    dh2 = OpenSSL::PKey::DH.new(der)
    assert_equal_params(dh, dh2)
    assert_no_key(dh2)
  end

  def test_to_pem
    dh = OpenSSL::TestUtils::TEST_KEY_DH1024
    pem = dh.to_pem
    dh2 = OpenSSL::PKey::DH.new(pem)
    assert_equal_params(dh, dh2)
    assert_no_key(dh2)
  end

  def test_public_key
    dh = OpenSSL::TestUtils::TEST_KEY_DH1024
    public_key = dh.public_key
    assert_no_key(public_key) #implies public_key.public? is false!
    assert_equal(dh.to_der, public_key.to_der)
    assert_equal(dh.to_pem, public_key.to_pem)
  end

  def test_generate_key
    dh = OpenSSL::TestUtils::TEST_KEY_DH1024.public_key # creates a copy
    assert_no_key(dh)
    dh.generate_key!
    assert_key(dh)
  end

  def test_key_exchange
    dh = OpenSSL::TestUtils::TEST_KEY_DH1024
    dh2 = dh.public_key
    dh.generate_key!
    dh2.generate_key!
    assert_equal(dh.compute_key(dh2.pub_key), dh2.compute_key(dh.pub_key))
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
end

end
