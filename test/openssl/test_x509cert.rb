# frozen_string_literal: true
require_relative "utils"

if defined?(OpenSSL)

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

    [
      @rsa1024, @rsa2048, @dsa256, @dsa512,
    ].each{|pk|
      cert = issue_cert(@ca, pk, 1, exts, nil, nil)
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
      ["authorityKeyIdentifier","issuer:always,keyid:always",false],
    ]
    ca_cert = issue_cert(@ca, @rsa2048, 1, ca_exts, nil, nil)
    keyid = get_subject_key_id(ca_cert.to_der, hex: false)
    assert_equal keyid, ca_cert.authority_key_identifier
    assert_equal keyid, ca_cert.subject_key_identifier
    ca_cert.extensions.each_with_index{|ext, i|
      assert_equal(ca_exts[i].first, ext.oid)
      assert_equal(ca_exts[i].last, ext.critical?)
    }

    ee1_exts = [
      ["keyUsage","Non Repudiation, Digital Signature, Key Encipherment",true],
      ["subjectKeyIdentifier","hash",false],
      ["authorityKeyIdentifier","issuer:always,keyid:always",false],
      ["extendedKeyUsage","clientAuth, emailProtection, codeSigning",false],
      ["subjectAltName","email:ee1@ruby-lang.org",false],
      ["authorityInfoAccess","caIssuers;URI:http://www.example.com/caIssuers,OCSP;URI:http://www.example.com/ocsp",false],
    ]
    ee1_cert = issue_cert(@ee1, @rsa1024, 2, ee1_exts, ca_cert, @rsa2048)
    assert_equal(ca_cert.subject.to_der, ee1_cert.issuer.to_der)
    ee1_cert.extensions.each_with_index{|ext, i|
      assert_equal(ee1_exts[i].first, ext.oid)
      assert_equal(ee1_exts[i].last, ext.critical?)
    }
    assert_nil(ee1_cert.crl_uris)

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.config = OpenSSL::Config.parse(<<~_cnf_)
      [crlDistPts]
      URI.1 = http://www.example.com/crl
      URI.2 = ldap://ldap.example.com/cn=ca?certificateRevocationList;binary
    _cnf_
    cdp_cert = generate_cert(@ee1, @rsa1024, 3, ca_cert)
    ef.subject_certificate = cdp_cert
    cdp_cert.add_extension(ef.create_extension("crlDistributionPoints", "@crlDistPts"))
    cdp_cert.sign(@rsa2048, "sha256")
    assert_equal(
      ["http://www.example.com/crl", "ldap://ldap.example.com/cn=ca?certificateRevocationList;binary"],
      cdp_cert.crl_uris
    )

    ef = OpenSSL::X509::ExtensionFactory.new
    aia_cert = generate_cert(@ee1, @rsa1024, 4, ca_cert)
    ef.subject_certificate = aia_cert
    aia_cert.add_extension(
      ef.create_extension(
        "authorityInfoAccess",
        "caIssuers;URI:http://www.example.com/caIssuers," \
        "caIssuers;URI:ldap://ldap.example.com/cn=ca?authorityInfoAccessCaIssuers;binary," \
        "OCSP;URI:http://www.example.com/ocsp," \
        "OCSP;URI:ldap://ldap.example.com/cn=ca?authorityInfoAccessOcsp;binary",
        false
      )
    )
    aia_cert.sign(@rsa2048, "sha256")
    assert_equal(
      ["http://www.example.com/caIssuers", "ldap://ldap.example.com/cn=ca?authorityInfoAccessCaIssuers;binary"],
      aia_cert.ca_issuer_uris
    )
    assert_equal(
      ["http://www.example.com/ocsp", "ldap://ldap.example.com/cn=ca?authorityInfoAccessOcsp;binary"],
      aia_cert.ocsp_uris
    )

    no_exts_cert = issue_cert(@ca, @rsa2048, 5, [], nil, nil)
    assert_equal nil, no_exts_cert.authority_key_identifier
    assert_equal nil, no_exts_cert.subject_key_identifier
    assert_equal nil, no_exts_cert.crl_uris
    assert_equal nil, no_exts_cert.ca_issuer_uris
    assert_equal nil, no_exts_cert.ocsp_uris
  end

  def test_invalid_extension
    integer = OpenSSL::ASN1::Integer.new(0)
    invalid_exts_cert = generate_cert(@ee1, @rsa1024, 1, nil)
    ["subjectKeyIdentifier", "authorityKeyIdentifier", "crlDistributionPoints", "authorityInfoAccess"].each do |ext|
      invalid_exts_cert.add_extension(
        OpenSSL::X509::Extension.new(ext, integer.to_der)
      )
    end

    assert_raise(OpenSSL::ASN1::ASN1Error, "invalid extension") {
      invalid_exts_cert.authority_key_identifier
    }
    assert_raise(OpenSSL::ASN1::ASN1Error, "invalid extension") {
      invalid_exts_cert.subject_key_identifier
    }
    assert_raise(OpenSSL::ASN1::ASN1Error, "invalid extension") {
      invalid_exts_cert.crl_uris
    }
    assert_raise(OpenSSL::ASN1::ASN1Error, "invalid extension") {
      invalid_exts_cert.ca_issuer_uris
    }
    assert_raise(OpenSSL::ASN1::ASN1Error, "invalid extension") {
      invalid_exts_cert.ocsp_uris
    }
  end

  def test_sign_and_verify_rsa_sha1
    cert = issue_cert(@ca, @rsa2048, 1, [], nil, nil, digest: "SHA1")
    assert_equal(false, cert.verify(@rsa1024))
    assert_equal(true,  cert.verify(@rsa2048))
    assert_equal(false, certificate_error_returns_false { cert.verify(@dsa256) })
    assert_equal(false, certificate_error_returns_false { cert.verify(@dsa512) })
    cert.serial = 2
    assert_equal(false, cert.verify(@rsa2048))
  rescue OpenSSL::X509::CertificateError # RHEL 9 disables SHA1
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
    cert = issue_cert(@ca, @rsa2048, 1, [], nil, nil, digest: OpenSSL::Digest.new('DSS1'))
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

  def test_dsa_with_sha2
    cert = issue_cert(@ca, @dsa256, 1, [], nil, nil, digest: "sha256")
    assert_equal("dsa_with_SHA256", cert.signature_algorithm)
    # TODO: need more tests for dsa + sha2

    # SHA1 is allowed from OpenSSL 1.0.0 (0.9.8 requires DSS1)
    cert = issue_cert(@ca, @dsa256, 1, [], nil, nil, digest: "sha1")
    assert_equal("dsaWithSHA1", cert.signature_algorithm)
  rescue OpenSSL::X509::CertificateError # RHEL 9 disables SHA1
  end

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

  def test_read_der_then_pem
    cert1 = issue_cert(@ca, @rsa2048, 1, [], nil, nil)
    exts = [
      # A new line before PEM block
      ["nsComment", "Another certificate:\n" + cert1.to_pem],
    ]
    cert2 = issue_cert(@ca, @rsa2048, 2, exts, nil, nil)

    assert_equal cert2, OpenSSL::X509::Certificate.new(cert2.to_der)
    assert_equal cert2, OpenSSL::X509::Certificate.new(cert2.to_pem)
  end

  def test_eq
    now = Time.now
    cacert = issue_cert(@ca, @rsa1024, 1, [], nil, nil,
                        not_before: now, not_after: now + 3600)
    cert1 = issue_cert(@ee1, @rsa2048, 2, [], cacert, @rsa1024,
                       not_before: now, not_after: now + 3600)
    cert2 = issue_cert(@ee1, @rsa2048, 2, [], cacert, @rsa1024,
                       not_before: now, not_after: now + 3600)
    cert3 = issue_cert(@ee1, @rsa2048, 3, [], cacert, @rsa1024,
                       not_before: now, not_after: now + 3600)
    cert4 = issue_cert(@ee1, @rsa2048, 2, [], cacert, @rsa1024,
                       digest: "sha512", not_before: now, not_after: now + 3600)

    assert_equal false, cert1 == 12345
    assert_equal true, cert1 == cert2
    assert_equal false, cert1 == cert3
    assert_equal false, cert1 == cert4
    assert_equal false, cert3 == cert4
  end

  def test_marshal
    now = Time.now
    cacert = issue_cert(@ca, @rsa1024, 1, [], nil, nil,
      not_before: now, not_after: now + 3600)
    cert = issue_cert(@ee1, @rsa2048, 2, [], cacert, @rsa1024,
      not_before: now, not_after: now + 3600)
    deserialized = Marshal.load(Marshal.dump(cert))

    assert_equal cert.to_der, deserialized.to_der
  end

  def test_load_file_empty_pem
    empty_path = Fixtures.file_path("pkey", "empty.pem")
    assert_raise(OpenSSL::X509::CertificateError) do
      OpenSSL::X509::Certificate.load_file(empty_path)
    end
  end

  def test_load_file_fullchain_pem
    fullchain_path = Fixtures.file_path("pkey", "fullchain.pem")
    certificates = OpenSSL::X509::Certificate.load_file(fullchain_path)
    assert_equal 2, certificates.size
    assert_equal "/CN=www.codeotaku.com", certificates[0].subject.to_s
    assert_equal "/C=US/O=Let's Encrypt/CN=R3", certificates[1].subject.to_s
  end

  def test_load_file_certificate_der
    fullchain_path = Fixtures.file_path("pkey", "certificate.der")
    certificates = OpenSSL::X509::Certificate.load_file(fullchain_path)

    # DER encoding can only contain one certificate:
    assert_equal 1, certificates.size
    assert_equal "/CN=www.codeotaku.com", certificates[0].subject.to_s
  end

  def test_load_file_fullchain_garbage
    fullchain_path = Fixtures.file_path("pkey", "garbage.txt")

    assert_raise(OpenSSL::X509::CertificateError) do
      OpenSSL::X509::Certificate.load_file(fullchain_path)
    end
  end

  private

  def certificate_error_returns_false
    yield
  rescue OpenSSL::X509::CertificateError
    false
  end
end

end
