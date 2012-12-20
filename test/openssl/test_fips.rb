require_relative 'utils'

if defined?(OpenSSL) && OpenSSL::OPENSSL_FIPS

class OpenSSL::TestFIPS < Test::Unit::TestCase
  
  def test_reject_md5
    data = "test"
    assert_not_nil(OpenSSL::Digest.new("MD5").digest(data))
    in_fips_mode do
      assert_raise(OpenSSL::Digest::DigestError) do
        OpenSSL::Digest.new("MD5").digest(data)
      end
    end
  end

  def test_reject_short_key_rsa
    assert_key_too_short(OpenSSL::PKey::RSAError) { dh = OpenSSL::PKey::RSA.new(256) }
  end

  def test_reject_short_key_dsa
    assert_key_too_short(OpenSSL::PKey::DSAError) { dh = OpenSSL::PKey::DSA.new(256) }
  end

  def test_reject_short_key_dh
    assert_key_too_short(OpenSSL::PKey::DHError) { dh = OpenSSL::PKey::DH.new(256) }
  end

  def test_reject_short_key_ec
    assert_key_too_short(OpenSSL::PKey::ECError) do
      group = OpenSSL::PKey::EC::Group.new('secp112r1')
      key = OpenSSL::PKey::EC.new
      key.group = group
      key.generate_key
    end
  end

  private
  
  def in_fips_mode
    OpenSSL.fips_mode = true
    yield
  ensure
    OpenSSL.fips_mode = false
  end

  def assert_key_too_short(expected_error)
    in_fips_mode do
      assert_raise(expected_error) { yield }
    end
  end

end

end
