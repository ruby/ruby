# coding: utf-8
# frozen_string_literal: true

require 'rubygems/test_case'

unless defined?(OpenSSL::SSL) then
  warn 'Skipping Gem::Security::Policy tests.  openssl not found.'
end

class TestGemSecurityPolicy < Gem::TestCase

  ALTERNATE_KEY    = load_key 'alternate'
  INVALID_KEY      = load_key 'invalid'
  CHILD_KEY        = load_key 'child'
  GRANDCHILD_KEY   = load_key 'grandchild'
  INVALIDCHILD_KEY = load_key 'invalidchild'

  ALTERNATE_CERT      = load_cert 'alternate'
  CA_CERT             = load_cert 'ca'
  CHILD_CERT          = load_cert 'child'
  EXPIRED_CERT        = load_cert 'expired'
  FUTURE_CERT         = load_cert 'future'
  GRANDCHILD_CERT     = load_cert 'grandchild'
  INVALIDCHILD_CERT   = load_cert 'invalidchild'
  INVALID_ISSUER_CERT = load_cert 'invalid_issuer'
  INVALID_SIGNER_CERT = load_cert 'invalid_signer'
  WRONG_KEY_CERT      = load_cert 'wrong_key'

  def setup
    super

    @spec = quick_gem 'a' do |s|
      s.description = 'π'
      s.files = %w[lib/code.rb]
    end

    @digest = Gem::Security::DIGEST_ALGORITHM
    @trust_dir = Gem::Security.trust_dir.dir # HACK use the object

    @no        = Gem::Security::NoSecurity
    @almost_no = Gem::Security::AlmostNoSecurity
    @low       = Gem::Security::LowSecurity
    @medium    = Gem::Security::MediumSecurity
    @high      = Gem::Security::HighSecurity

    @chain = Gem::Security::Policy.new(
      'Chain',
      :verify_data   => true,
      :verify_signer => true,
      :verify_chain  => true,
      :verify_root   => false,
      :only_trusted  => false,
      :only_signed   => false
    )

    @root = Gem::Security::Policy.new(
      'Root',
      :verify_data   => true,
      :verify_signer => true,
      :verify_chain  => true,
      :verify_root   => true,
      :only_trusted  => false,
      :only_signed   => false
    )
  end

  def test_check_data
    data = digest 'hello'

    signature = sign data

    assert @almost_no.check_data(PUBLIC_KEY, @digest, signature, data)
  end

  def test_check_data_invalid
    data = digest 'hello'

    signature = sign data

    invalid = digest 'hello!'

    e = assert_raises Gem::Security::Exception do
      @almost_no.check_data PUBLIC_KEY, @digest, signature, invalid
    end

    assert_equal 'invalid signature', e.message
  end

  def test_check_chain
    chain = [PUBLIC_CERT, CHILD_CERT, GRANDCHILD_CERT]

    assert @chain.check_chain chain, Time.now
  end

  def test_check_chain_empty_chain
    e = assert_raises Gem::Security::Exception do
      @chain.check_chain [], Time.now
    end

    assert_equal 'empty signing chain', e.message
  end

  def test_check_chain_invalid
    chain = [PUBLIC_CERT, CHILD_CERT, INVALIDCHILD_CERT]

    e = assert_raises Gem::Security::Exception do
      @chain.check_chain chain, Time.now
    end

    assert_equal "invalid signing chain: " +
                 "certificate #{INVALIDCHILD_CERT.subject} " +
                 "was not issued by #{CHILD_CERT.subject}", e.message
  end

  def test_check_chain_no_chain
    e = assert_raises Gem::Security::Exception do
      @chain.check_chain nil, Time.now
    end

    assert_equal 'missing signing chain', e.message
  end

  def test_check_cert
    assert @low.check_cert(PUBLIC_CERT, nil, Time.now)
  end

  def test_check_cert_expired
    e = assert_raises Gem::Security::Exception do
      @low.check_cert EXPIRED_CERT, nil, Time.now
    end

    assert_equal "certificate #{EXPIRED_CERT.subject} " +
                 "not valid after #{EXPIRED_CERT.not_after}",
                 e.message
  end

  def test_check_cert_future
    e = assert_raises Gem::Security::Exception do
      @low.check_cert FUTURE_CERT, nil, Time.now
    end

    assert_equal "certificate #{FUTURE_CERT.subject} " +
                 "not valid before #{FUTURE_CERT.not_before}",
                 e.message
  end

  def test_check_cert_invalid_issuer
    e = assert_raises Gem::Security::Exception do
      @low.check_cert INVALID_ISSUER_CERT, PUBLIC_CERT, Time.now
    end

    assert_equal "certificate #{INVALID_ISSUER_CERT.subject} " +
                 "was not issued by #{PUBLIC_CERT.subject}",
                 e.message
  end

  def test_check_cert_issuer
    assert @low.check_cert(CHILD_CERT, PUBLIC_CERT, Time.now)
  end

  def test_check_cert_no_signer
    e = assert_raises Gem::Security::Exception do
      @high.check_cert(nil, nil, Time.now)
    end

    assert_equal 'missing signing certificate', e.message
  end

  def test_check_key
    assert @almost_no.check_key(PUBLIC_CERT, PRIVATE_KEY)
  end

  def test_check_key_no_signer
    assert @almost_no.check_key(nil, nil)

    e = assert_raises Gem::Security::Exception do
      @high.check_key(nil, nil)
    end

    assert_equal 'missing key or signature', e.message
  end

  def test_check_key_wrong_key
    e = assert_raises Gem::Security::Exception do
      @almost_no.check_key(PUBLIC_CERT, ALTERNATE_KEY)
    end

    assert_equal "certificate #{PUBLIC_CERT.subject} " +
                 "does not match the signing key", e.message
  end

  def test_check_root
    chain = [PUBLIC_CERT, CHILD_CERT, INVALIDCHILD_CERT]

    assert @chain.check_root chain, Time.now
  end

  def test_check_root_empty_chain
    e = assert_raises Gem::Security::Exception do
      @chain.check_root [], Time.now
    end

    assert_equal 'missing root certificate', e.message
  end

  def test_check_root_invalid_signer
    chain = [INVALID_SIGNER_CERT]

    e = assert_raises Gem::Security::Exception do
      @chain.check_root chain, Time.now
    end

    assert_equal "certificate #{INVALID_SIGNER_CERT.subject} " +
                 "was not issued by #{INVALID_SIGNER_CERT.issuer}",
                 e.message
  end

  def test_check_root_not_self_signed
    chain = [INVALID_ISSUER_CERT]

    e = assert_raises Gem::Security::Exception do
      @chain.check_root chain, Time.now
    end

    assert_equal "root certificate #{INVALID_ISSUER_CERT.subject} " +
                 "is not self-signed (issuer #{INVALID_ISSUER_CERT.issuer})",
                 e.message
  end

  def test_check_root_no_chain
    e = assert_raises Gem::Security::Exception do
      @chain.check_root nil, Time.now
    end

    assert_equal 'missing signing chain', e.message
  end

  def test_check_trust
    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    assert @high.check_trust [PUBLIC_CERT], @digest, @trust_dir
  end

  def test_check_trust_child
    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    assert @high.check_trust [PUBLIC_CERT, CHILD_CERT], @digest, @trust_dir
  end

  def test_check_trust_empty_chain
    e = assert_raises Gem::Security::Exception do
      @chain.check_trust [], @digest, @trust_dir
    end

    assert_equal 'missing root certificate', e.message
  end

  def test_check_trust_mismatch
    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    e = assert_raises Gem::Security::Exception do
      @high.check_trust [WRONG_KEY_CERT], @digest, @trust_dir
    end

    assert_equal "trusted root certificate #{PUBLIC_CERT.subject} checksum " +
                 "does not match signing root certificate checksum", e.message
  end

  def test_check_trust_no_chain
    e = assert_raises Gem::Security::Exception do
      @chain.check_trust nil, @digest, @trust_dir
    end

    assert_equal 'missing signing chain', e.message
  end

  def test_check_trust_no_trust
    e = assert_raises Gem::Security::Exception do
      @high.check_trust [PUBLIC_CERT], @digest, @trust_dir
    end

    assert_equal "root cert #{PUBLIC_CERT.subject} is not trusted", e.message
  end

  def test_check_trust_no_trust_child
    e = assert_raises Gem::Security::Exception do
      @high.check_trust [PUBLIC_CERT, CHILD_CERT], @digest, @trust_dir
    end

    assert_equal "root cert #{PUBLIC_CERT.subject} is not trusted " +
                 "(root of signing cert #{CHILD_CERT.subject})", e.message
  end

  def test_subject
    assert_equal 'email:nobody@example', @no.subject(PUBLIC_CERT)
    assert_equal '/C=JP/O=JIN.GR.JP/OU=RRR/CN=CA', @no.subject(CA_CERT)
  end

  def test_verify
    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    assert @almost_no.verify [PUBLIC_CERT], nil, *dummy_signatures
  end

  def test_verify_chain_signatures
    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    assert @high.verify [PUBLIC_CERT], nil, *dummy_signatures
  end

  def test_verify_chain_key
    @almost_no.verify [PUBLIC_CERT], PRIVATE_KEY, *dummy_signatures
  end

  def test_verify_no_digests
    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    _, signatures = dummy_signatures

    e = assert_raises Gem::Security::Exception do
      @almost_no.verify [PUBLIC_CERT], nil, {}, signatures
    end

    assert_equal 'no digests provided (probable bug)', e.message
  end

  def test_verify_no_digests_no_security
    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    _, signatures = dummy_signatures

    e = assert_raises Gem::Security::Exception do
      @no.verify [PUBLIC_CERT], nil, {}, signatures
    end

    assert_equal 'missing digest for 0', e.message
  end

  def test_verify_no_signatures
    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    digests, = dummy_signatures

    use_ui @ui do
      @no.verify [PUBLIC_CERT], nil, digests, {}, 'some_gem'
    end

    assert_match "WARNING:  some_gem is not signed\n", @ui.error

    assert_raises Gem::Security::Exception do
      @high.verify [PUBLIC_CERT], nil, digests, {}
    end
  end

  def test_verify_no_signatures_no_digests
    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    use_ui @ui do
      @no.verify [PUBLIC_CERT], nil, {}, {}, 'some_gem'
    end

    assert_empty @ui.output
    assert_empty @ui.error
  end

  def test_verify_not_enough_signatures
    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    digests, signatures = dummy_signatures

    data = digest 'goodbye'

    signatures[1] = PRIVATE_KEY.sign @digest.new, data.digest

    e = assert_raises Gem::Security::Exception do
      @almost_no.verify [PUBLIC_CERT], nil, digests, signatures
    end

    assert_equal 'missing digest for 1', e.message
  end

  def test_verify_no_trust
    digests, signatures = dummy_signatures

    use_ui @ui do
      @low.verify [PUBLIC_CERT], nil, digests, signatures, 'some_gem'
    end

    assert_equal "WARNING:  email:nobody@example is not trusted for some_gem\n",
                 @ui.error

    assert_raises Gem::Security::Exception do
      @medium.verify [PUBLIC_CERT], nil, digests, signatures
    end
  end

  def test_verify_wrong_digest_type
    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    sha512 = OpenSSL::Digest::SHA512

    data = sha512.new
    data << 'hello'

    digests    = { 'SHA512' => { 0 => data } }
    signature  = PRIVATE_KEY.sign sha512.new, data.digest
    signatures = { 0 => signature }

    e = assert_raises Gem::Security::Exception do
      @almost_no.verify [PUBLIC_CERT], nil, digests, signatures
    end

    assert_equal 'no digests provided (probable bug)', e.message
  end

  def test_verify_signatures_chain
    @spec.cert_chain = [PUBLIC_CERT, CHILD_CERT]

    assert @chain.verify_signatures @spec, *dummy_signatures(CHILD_KEY)
  end

  def test_verify_signatures_data
    @spec.cert_chain = [PUBLIC_CERT]

    @almost_no.verify_signatures @spec, *dummy_signatures
  end

  def test_verify_signatures_root
    @spec.cert_chain = [PUBLIC_CERT, CHILD_CERT]

    assert @root.verify_signatures @spec, *dummy_signatures(CHILD_KEY)
  end

  def test_verify_signatures_signer
    @spec.cert_chain = [PUBLIC_CERT]

    assert @low.verify_signatures @spec, *dummy_signatures
  end

  def test_verify_signatures_trust
    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    @spec.cert_chain = [PUBLIC_CERT]

    assert @high.verify_signatures @spec, *dummy_signatures
  end

  def test_verify_signatures
    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    @spec.cert_chain = [PUBLIC_CERT.to_s]

    metadata_gz = Gem.gzip @spec.to_yaml

    package = Gem::Package.new 'nonexistent.gem'
    package.checksums[Gem::Security::DIGEST_NAME] = {}

    s = StringIO.new metadata_gz
    def s.full_name() 'metadata.gz' end

    digests = package.digest s
    metadata_gz_digest = digests[Gem::Security::DIGEST_NAME]['metadata.gz']

    signatures = {}
    signatures['metadata.gz'] =
      PRIVATE_KEY.sign @digest.new, metadata_gz_digest.digest

    assert @high.verify_signatures @spec, digests, signatures
  end

  def test_verify_signatures_missing
    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    @spec.cert_chain = [PUBLIC_CERT.to_s]

    metadata_gz = Gem.gzip @spec.to_yaml

    package = Gem::Package.new 'nonexistent.gem'
    package.checksums[Gem::Security::DIGEST_NAME] = {}

    s = StringIO.new metadata_gz
    def s.full_name() 'metadata.gz' end

    digests = package.digest s
    digests[Gem::Security::DIGEST_NAME]['data.tar.gz'] = @digest.new 'hello'

    metadata_gz_digest = digests[Gem::Security::DIGEST_NAME]['metadata.gz']

    signatures = {}
    signatures['metadata.gz'] =
      PRIVATE_KEY.sign @digest.new, metadata_gz_digest.digest

    e = assert_raises Gem::Security::Exception do
      @high.verify_signatures @spec, digests, signatures
    end

    assert_equal 'missing signature for data.tar.gz', e.message
  end

  def test_verify_signatures_none
    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    @spec.cert_chain = [PUBLIC_CERT.to_s]

    metadata_gz = Gem.gzip @spec.to_yaml

    package = Gem::Package.new 'nonexistent.gem'
    package.checksums[Gem::Security::DIGEST_NAME] = {}

    s = StringIO.new metadata_gz
    def s.full_name() 'metadata.gz' end

    digests = package.digest s
    digests[Gem::Security::DIGEST_NAME]['data.tar.gz'] = @digest.new 'hello'

    assert_raises Gem::Security::Exception do
      @high.verify_signatures @spec, digests, {}
    end
  end

  def digest data
    digester = @digest.new
    digester << data
    digester
  end

  def sign data, key = PRIVATE_KEY
    key.sign @digest.new, data.digest
  end

  def dummy_signatures key = PRIVATE_KEY
    data = digest 'hello'

    digests    = { Gem::Security::DIGEST_NAME => { 0 => data } }
    signatures = { 0 => sign(data, key) }

    return digests, signatures
  end

end if defined?(OpenSSL::SSL)

