# frozen_string_literal: true
require 'rubygems/test_case'

unless defined?(OpenSSL::SSL)
  warn 'Skipping Gem::Security::Signer tests.  openssl not found.'
end

class TestGemSecuritySigner < Gem::TestCase
  ALTERNATE_KEY  = load_key 'alternate'
  CHILD_KEY      = load_key 'child'
  GRANDCHILD_KEY = load_key 'grandchild'

  CHILD_CERT      = load_cert 'child'
  GRANDCHILD_CERT = load_cert 'grandchild'
  EXPIRED_CERT    = load_cert 'expired'

  def setup
    super

    @cert_file = PUBLIC_CERT
  end

  def test_initialize
    signer = Gem::Security::Signer.new nil, nil

    assert_nil signer.key
    assert_nil signer.cert_chain
  end

  def test_initialize_cert_chain_empty
    signer = Gem::Security::Signer.new PUBLIC_KEY, []

    assert_empty signer.cert_chain
  end

  def test_initialize_cert_chain_mixed
    signer = Gem::Security::Signer.new nil, [@cert_file, CHILD_CERT]

    assert_equal [PUBLIC_CERT, CHILD_CERT].map {|c| c.to_pem },
                 signer.cert_chain.map {|c| c.to_pem }
  end

  def test_initialize_cert_chain_invalid
    assert_raises OpenSSL::X509::CertificateError do
      Gem::Security::Signer.new nil, ['garbage']
    end
  end

  def test_initialize_cert_chain_path
    signer = Gem::Security::Signer.new nil, [@cert_file]

    assert_equal [PUBLIC_CERT].map {|c| c.to_pem },
                 signer.cert_chain.map {|c| c.to_pem }
  end

  def test_initialize_default
    FileUtils.mkdir_p File.join(Gem.user_home, '.gem')

    private_key_path = File.join Gem.user_home, '.gem', 'gem-private_key.pem'
    Gem::Security.write PRIVATE_KEY, private_key_path

    public_cert_path = File.join Gem.user_home, '.gem', 'gem-public_cert.pem'
    Gem::Security.write PUBLIC_CERT, public_cert_path

    signer = Gem::Security::Signer.new nil, nil

    assert_equal PRIVATE_KEY.to_pem, signer.key.to_pem
    assert_equal [PUBLIC_CERT.to_pem], signer.cert_chain.map {|c| c.to_pem }
  end

  def test_initialize_key_path
    key_file = PRIVATE_KEY_PATH

    signer = Gem::Security::Signer.new key_file, nil

    assert_equal PRIVATE_KEY.to_s, signer.key.to_s
  end

  def test_initialize_encrypted_key_path
    key_file = ENCRYPTED_PRIVATE_KEY_PATH

    signer = Gem::Security::Signer.new key_file, nil, PRIVATE_KEY_PASSPHRASE

    assert_equal ENCRYPTED_PRIVATE_KEY.to_s, signer.key.to_s
  end

  def test_extract_name
    signer = Gem::Security::Signer.new nil, nil

    assert_equal 'child@example', signer.extract_name(CHILD_CERT)
  end

  def test_load_cert_chain
    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    signer = Gem::Security::Signer.new nil, []
    signer.cert_chain.replace [CHILD_CERT]

    signer.load_cert_chain

    assert_equal [PUBLIC_CERT.to_pem, CHILD_CERT.to_pem],
                 signer.cert_chain.map {|c| c.to_pem }
  end

  def test_load_cert_chain_broken
    Gem::Security.trust_dir.trust_cert CHILD_CERT

    signer = Gem::Security::Signer.new nil, []
    signer.cert_chain.replace [GRANDCHILD_CERT]

    signer.load_cert_chain

    assert_equal [CHILD_CERT.to_pem, GRANDCHILD_CERT.to_pem],
                 signer.cert_chain.map {|c| c.to_pem }
  end

  def test_sign
    signer = Gem::Security::Signer.new PRIVATE_KEY, [PUBLIC_CERT]

    signature = signer.sign 'hello'

    expected = <<-EXPECTED
cHze2sEfRysoUMCfGVAx/7o8jxj5liJJ2ptNxe2jf3l+EZvyjdqpXo9Ndzxx
6xLp2rxLG4K2//ip4aCH5Sh7hnia+F5u6iuLBETPlklPrmw5dnuKZxolz+vM
0O1aOZsQHcVzQoESTGjkms3KZk+gn3lg0sSBbAV5/LyDYoHCEjxlcA5D+Olb
rDmRyBMOnMS+q489OZ5Hr6B2YJJ3QbUwIZNhUeNmOxIBEYTrrKkZ92qkxbRN
qhlqFP4jR6zXFeyBCOr0KpTiWBNuxBFXDsxmhGyt2BOIjD6qmKn7RSIfYg/U
toqvglr0kdbknSRRjBVLK6tsgr07aLT9gNP7mTW2PA==
    EXPECTED

    assert_equal expected, [signature].pack('m')
  end

  def test_sign_expired
    signer = Gem::Security::Signer.new PRIVATE_KEY, [EXPIRED_CERT]

    e = assert_raises Gem::Security::Exception do
      signer.sign 'hello'
    end

    assert_match "certificate /CN=nobody/DC=example not valid after 1970-01-01 00:00:00 UTC", e.message
  end

  def test_sign_expired_auto_update
    skip if Gem.java_platform?
    FileUtils.mkdir_p File.join(Gem.user_home, '.gem'), :mode => 0700

    private_key_path = File.join(Gem.user_home, '.gem', 'gem-private_key.pem')
    Gem::Security.write PRIVATE_KEY, private_key_path

    cert_path = File.join Gem.user_home, '.gem', 'gem-public_cert.pem'
    Gem::Security.write EXPIRED_CERT, cert_path

    signer = Gem::Security::Signer.new PRIVATE_KEY, [EXPIRED_CERT]

    signer.sign 'hello'

    cert = OpenSSL::X509::Certificate.new File.read cert_path

    refute_equal EXPIRED_CERT.to_pem, cert.to_pem
    assert_in_delta Time.now,         cert.not_before, 10

    expiry = EXPIRED_CERT.not_after.strftime "%Y%m%d%H%M%S"

    expired_path =
      File.join Gem.user_home, '.gem', "gem-public_cert.pem.expired.#{expiry}"

    assert_path_exists expired_path
    assert_equal EXPIRED_CERT.to_pem, File.read(expired_path)
  end

  def test_sign_expired_auto_update_exists
    FileUtils.mkdir_p File.join(Gem.user_home, '.gem'), :mode => 0700

    expiry = EXPIRED_CERT.not_after.strftime "%Y%m%d%H%M%S"
    expired_path =
      File.join Gem.user_home, "gem-public_cert.pem.expired.#{expiry}"

    Gem::Security.write EXPIRED_CERT, expired_path

    private_key_path = File.join(Gem.user_home, 'gem-private_key.pem')
    Gem::Security.write PRIVATE_KEY, private_key_path

    cert_path = File.join Gem.user_home, 'gem-public_cert.pem'
    Gem::Security.write EXPIRED_CERT, cert_path

    signer = Gem::Security::Signer.new PRIVATE_KEY, [EXPIRED_CERT]

    e = assert_raises Gem::Security::Exception do
      signer.sign 'hello'
    end

    assert_match %r{certificate /CN=nobody/DC=example not valid}, e.message
  end

  def test_sign_no_key
    signer = Gem::Security::Signer.new nil, nil

    assert_nil signer.sign 'stuff'
  end

  def test_sign_wrong_key
    signer = Gem::Security::Signer.new ALTERNATE_KEY, [PUBLIC_CERT]

    assert_raises Gem::Security::Exception do
      signer.sign 'hello'
    end
  end

  def test_sign_no_certs
    signer = Gem::Security::Signer.new ALTERNATE_KEY, []

    assert_raises Gem::Security::Exception do
      signer.sign 'hello'
    end
  end
end if defined?(OpenSSL::SSL)
