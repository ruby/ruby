require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestPKeyEC < Test::Unit::TestCase
  def test_new
    group = OpenSSL::PKey::EC::Group.new('prime256v1')
    ec = OpenSSL::PKey::EC.new(group)
    ec.generate_key
    assert(ec.private_key?)
    assert(ec.public_key?)
  end

  def test_read_private_key_der
    ec = OpenSSL::TestUtils::TEST_KEY_EC_P256V1
    der = ec.to_der
    ec2 = OpenSSL::PKey.read(der)
    assert(ec2.private_key?)
    assert_equal(der, ec2.to_der)
  end

  def test_read_private_key_pem
    ec = OpenSSL::TestUtils::TEST_KEY_EC_P256V1
    pem = ec.to_pem
    ec2 = OpenSSL::PKey.read(pem)
    assert(ec2.private_key?)
    assert_equal(pem, ec2.to_pem)
  end

  def test_read_public_key_der
    ec = OpenSSL::TestUtils::TEST_KEY_EC_P256V1
    group = OpenSSL::PKey::EC::Group.new('prime256v1')
    ec2 = OpenSSL::PKey::EC.new(group)
    ec2.public_key = ec.public_key
    der = ec2.to_der
    ec3 = OpenSSL::PKey.read(der)
    assert(!ec3.private_key?)
    assert_equal(der, ec3.to_der)
  end

  def test_read_public_key_pem
    ec = OpenSSL::TestUtils::TEST_KEY_EC_P256V1
    group = OpenSSL::PKey::EC::Group.new('prime256v1')
    ec2 = OpenSSL::PKey::EC.new(group)
    ec2.public_key = ec.public_key
    pem = ec2.to_pem
    ec3 = OpenSSL::PKey.read(pem)
    assert(!ec3.private_key?)
    assert_equal(pem, ec3.to_pem)
  end

  def test_read_private_key_pem_pw
    ec = OpenSSL::TestUtils::TEST_KEY_EC_P256V1
    pem = ec.to_pem(OpenSSL::Cipher.new('AES-128-CBC'), 'secret')
    #callback form for password
    ec2 = OpenSSL::PKey.read(pem) do
      'secret'
    end
    assert(ec2.private_key?)
    # pass password directly
    ec2 = OpenSSL::PKey.read(pem, 'secret')
    assert(ec2.private_key?)
    #omit pem equality check, will be different due to cipher iv
  end

end

end
