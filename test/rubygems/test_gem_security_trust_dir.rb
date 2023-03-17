# frozen_string_literal: true

require_relative "helper"

unless Gem::HAVE_OPENSSL
  warn "Skipping Gem::Security::TrustDir tests.  openssl not found."
end

class TestGemSecurityTrustDir < Gem::TestCase
  CHILD_CERT = load_cert "child"

  def setup
    super

    @dest_dir = File.join @tempdir, "trust"

    @trust_dir = Gem::Security::TrustDir.new @dest_dir
  end

  def test_cert_path
    digest = OpenSSL::Digest.hexdigest Gem::Security::DIGEST_NAME, PUBLIC_CERT.subject.to_s

    expected = File.join @dest_dir, "cert-#{digest}.pem"

    assert_equal expected, @trust_dir.cert_path(PUBLIC_CERT)
  end

  def test_issuer_of
    assert_nil @trust_dir.issuer_of(CHILD_CERT)

    @trust_dir.trust_cert PUBLIC_CERT

    assert_equal PUBLIC_CERT.to_pem, @trust_dir.issuer_of(CHILD_CERT).to_pem
  end

  def test_load_certificate
    @trust_dir.trust_cert PUBLIC_CERT

    path = @trust_dir.cert_path PUBLIC_CERT

    assert_equal PUBLIC_CERT.to_pem, @trust_dir.load_certificate(path).to_pem
  end

  def test_name_path
    digest = OpenSSL::Digest.hexdigest Gem::Security::DIGEST_NAME, PUBLIC_CERT.subject.to_s

    expected = File.join @dest_dir, "cert-#{digest}.pem"

    assert_equal expected, @trust_dir.name_path(PUBLIC_CERT.subject)
  end

  def test_trust_cert
    @trust_dir.trust_cert PUBLIC_CERT

    trusted = @trust_dir.cert_path PUBLIC_CERT

    assert_path_exist trusted

    mask = 0100600 & (~File.umask)

    assert_equal mask, File.stat(trusted).mode unless win_platform?

    assert_equal PUBLIC_CERT.to_pem, File.read(trusted)
  end

  def test_verify
    assert_path_not_exist @dest_dir

    @trust_dir.verify

    assert_path_exist @dest_dir

    mask = 040700 & (~File.umask)
    mask |= 0200000 if RUBY_PLATFORM.include?("aix")

    assert_equal mask, File.stat(@dest_dir).mode unless win_platform?
  end

  def test_verify_file
    FileUtils.touch @dest_dir

    e = assert_raise Gem::Security::Exception do
      @trust_dir.verify
    end

    assert_equal "trust directory #{@dest_dir} is not a directory", e.message
  end

  def test_verify_wrong_permissions
    FileUtils.mkdir_p @dest_dir, :mode => 0777

    @trust_dir.verify

    mask = 040700 & (~File.umask)
    mask |= 0200000 if RUBY_PLATFORM.include?("aix")

    assert_equal mask, File.stat(@dest_dir).mode unless win_platform?
  end
end if Gem::HAVE_OPENSSL
