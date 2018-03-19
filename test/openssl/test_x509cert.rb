# frozen_string_literal: false
require_relative "utils"

if defined?(OpenSSL::TestUtils)

class OpenSSL::TestX509Certificate < OpenSSL::TestCase
  def setup
    super
    @rsa1024 = Fixtures.pkey("rsa1024")
    @rsa2048 = Fixtures.pkey("rsa2048")
    @dsa256  = Fixtures.pkey("dsa256")
    @dsa512  = Fixtures.pkey("dsa512")
    @ca = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=CA")
    @ee1 = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=EE1")
  end

  def test_serial
    [1, 2**32, 2**100].each{|s|
      cert = issue_cert(@ca, @rsa2048, s, [], nil, nil)
      assert_equal(s, cert.serial)
      cert = OpenSSL::X509::Certificate.new(cert.to_der)
      assert_equal(s, cert.serial)
    }
  end

  def test_public_key
    exts = [
      ["basicConstraints","CA:TRUE",true],
      ["subjectKeyIdentifier","hash",false],
      ["authorityKeyIdentifier","keyid:always",false],
    ]

    sha1 = OpenSSL::Digest::SHA1.new
    dsa_digest = OpenSSL::TestUtils::DSA_SIGNATURE_DIGEST.new

    [
      [@rsa1024, sha1], [@rsa2048, sha1], [@dsa256, dsa_digest], [@dsa512, dsa_digest]
    ].each{|pk, digest|
      cert = issue_cert(@ca, pk, 1, exts, nil, nil, digest: digest)
      assert_equal(cert.extensions.sort_by(&:to_s)[2].value,
                   OpenSSL::TestUtils.get_subject_key_id(cert))
      cert = OpenSSL::X509::Certificate.new(cert.to_der)
      assert_equal(cert.extensions.sort_by(&:to_s)[2].value,
                   OpenSSL::TestUtils.get_subject_key_id(cert))
    }
  end

  def test_validity
    now = Time.at(Time.now.to_i + 0.9)
    cert = issue_cert(@ca, @rsa2048, 1, [], nil, nil,
                      not_before: now, not_after: now+3600)
    assert_equal(Time.at(now.to_i), cert.not_before)
    assert_equal(Time.at(now.to_i+3600), cert.not_after)

    now = Time.at(now.to_i)
    cert = issue_cert(@ca, @rsa2048, 1, [], nil, nil,
                      not_before: now, not_after: now+3600)
    assert_equal(now.getutc, cert.not_before)
    assert_equal((now+3600).getutc, cert.not_after)

    now = Time.at(0)
    cert = issue_cert(@ca, @rsa2048, 1, [], nil, nil,
                      not_before: now, not_after: now)
    assert_equal(now.getutc, cert.not_before)
    assert_equal(now.getutc, cert.not_after)

    now = Time.at(0x7fffffff)
    cert = issue_cert(@ca, @rsa2048, 1, [], nil, nil,
                      not_before: now, not_after: now)
    assert_equal(now.getutc, cert.not_before)
    assert_equal(now.getutc, cert.not_after)
  end

  def test_extension
    ca_exts = [
      ["basicConstraints","CA:TRUE",true],
      ["keyUsage","keyCertSign, cRLSign",true],
      ["subjectKeyIdentifier","hash",false],
      ["authorityKeyIdentifier","keyid:always",false],
    ]
    ca_cert = issue_cert(@ca, @rsa2048, 1, ca_exts, nil, nil)
    ca_cert.extensions.each_with_index{|ext, i|
      assert_equal(ca_exts[i].first, ext.oid)
      assert_equal(ca_exts[i].last, ext.critical?)
    }

    ee1_exts = [
      ["keyUsage","Non Repudiation, Digital Signature, Key Encipherment",true],
      ["subjectKeyIdentifier","hash",false],
      ["authorityKeyIdentifier","keyid:always",false],
      ["extendedKeyUsage","clientAuth, emailProtection, codeSigning",false],
      ["subjectAltName","email:ee1@ruby-lang.org",false],
    ]
    ee1_cert = issue_cert(@ee1, @rsa1024, 2, ee1_exts, ca_cert, @rsa2048)
    assert_equal(ca_cert.subject.to_der, ee1_cert.issuer.to_der)
    ee1_cert.extensions.each_with_index{|ext, i|
      assert_equal(ee1_exts[i].first, ext.oid)
      assert_equal(ee1_exts[i].last, ext.critical?)
    }
  end

  def test_sign_and_verify_rsa_sha1
    cert = issue_cert(@ca, @rsa2048, 1, [], nil, nil, digest: "sha1")
    assert_equal(false, cert.verify(@rsa1024))
    assert_equal(true,  cert.verify(@rsa2048))
    assert_equal(false, certificate_error_returns_false { cert.verify(@dsa256) })
    assert_equal(false, certificate_error_returns_false { cert.verify(@dsa512) })
    cert.serial = 2
    assert_equal(false, cert.verify(@rsa2048))
  end

  def test_sign_and_verify_rsa_md5
    cert = issue_cert(@ca, @rsa2048, 1, [], nil, nil, digest: "md5")
    assert_equal(false, cert.verify(@rsa1024))
    assert_equal(true, cert.verify(@rsa2048))

    assert_equal(false, certificate_error_returns_false { cert.verify(@dsa256) })
    assert_equal(false, certificate_error_returns_false { cert.verify(@dsa512) })
    cert.subject = @ee1
    assert_equal(false, cert.verify(@rsa2048))
  rescue OpenSSL::X509::CertificateError # RHEL7 disables MD5
  end

  def test_sign_and_verify_dsa
    cert = issue_cert(@ca, @dsa512, 1, [], nil, nil)
    assert_equal(false, certificate_error_returns_false { cert.verify(@rsa1024) })
    assert_equal(false, certificate_error_returns_false { cert.verify(@rsa2048) })
    assert_equal(false, cert.verify(@dsa256))
    assert_equal(true,  cert.verify(@dsa512))
    cert.not_after = Time.now
    assert_equal(false, cert.verify(@dsa512))
  end

  def test_sign_and_verify_rsa_dss1
    cert = issue_cert(@ca, @rsa2048, 1, [], nil, nil, digest: OpenSSL::Digest::DSS1.new)
    assert_equal(false, cert.verify(@rsa1024))
    assert_equal(true, cert.verify(@rsa2048))
    assert_equal(false, certificate_error_returns_false { cert.verify(@dsa256) })
    assert_equal(false, certificate_error_returns_false { cert.verify(@dsa512) })
    cert.subject = @ee1
    assert_equal(false, cert.verify(@rsa2048))
  rescue OpenSSL::X509::CertificateError
  end if defined?(OpenSSL::Digest::DSS1)

  def test_sign_and_verify_dsa_md5
    assert_raise(OpenSSL::X509::CertificateError){
      issue_cert(@ca, @dsa512, 1, [], nil, nil, digest: "md5")
    }
  end

  def test_dsig_algorithm_mismatch
    assert_raise(OpenSSL::X509::CertificateError) do
      issue_cert(@ca, @rsa2048, 1, [], nil, nil, digest: OpenSSL::Digest::DSS1.new)
    end if OpenSSL::OPENSSL_VERSION_NUMBER < 0x10001000 # [ruby-core:42949]
  end

  def test_dsa_with_sha2
    begin
      cert = issue_cert(@ca, @dsa256, 1, [], nil, nil, digest: "sha256")
      assert_equal("dsa_with_SHA256", cert.signature_algorithm)
    rescue OpenSSL::X509::CertificateError
      # dsa_with_sha2 not supported. skip following test.
      return
    end
    # TODO: need more tests for dsa + sha2

    # SHA1 is allowed from OpenSSL 1.0.0 (0.9.8 requires DSS1)
    cert = issue_cert(@ca, @dsa256, 1, [], nil, nil, digest: "sha1")
    assert_equal("dsaWithSHA1", cert.signature_algorithm)
  end if defined?(OpenSSL::Digest::SHA256)

  def test_check_private_key
    cert = issue_cert(@ca, @rsa2048, 1, [], nil, nil)
    assert_equal(true, cert.check_private_key(@rsa2048))
  end

  def test_read_from_file
    cert = issue_cert(@ca, @rsa2048, 1, [], nil, nil)
    Tempfile.create("cert") { |f|
      f << cert.to_pem
      f.rewind
      assert_equal cert.to_der, OpenSSL::X509::Certificate.new(f).to_der
    }
  end

  private

  def certificate_error_returns_false
    yield
  rescue OpenSSL::X509::CertificateError
    false
  end
end

end
