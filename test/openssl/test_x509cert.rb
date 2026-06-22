# frozen_string_literal: true
require_relative "utils"

if defined?(OpenSSL)

class OpenSSL::TestX509Certificate < OpenSSL::TestCase
  def setup
    super
    @rsa1 = Fixtures.pkey("rsa-1")
    @rsa2 = Fixtures.pkey("rsa-2")
    @ec1 = Fixtures.pkey("p256")
    @ca = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=CA")
    @ee1 = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=EE1")
  end

  def test_serial
    [1, 2**32, 2**100].each{|s|
      cert = issue_cert(@ca, @rsa1, s, [], nil, nil)
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
    cert = issue_cert(@ca, @rsa1, 1, exts, nil, nil)
    assert_kind_of(OpenSSL::PKey::RSA, cert.public_key)
    assert_equal(@rsa1.public_to_der, cert.public_key.public_to_der)
    cert = OpenSSL::X509::Certificate.new(cert.to_der)
    assert_equal(@rsa1.public_to_der, cert.public_key.public_to_der)
  end

  def test_validity
    now = Time.at(Time.now.to_i + 0.9)
    cert = issue_cert(@ca, @rsa1, 1, [], nil, nil,
                      not_before: now, not_after: now+3600)
    assert_equal(Time.at(now.to_i), cert.not_before)
    assert_equal(Time.at(now.to_i+3600), cert.not_after)

    now = Time.at(now.to_i)
    cert = issue_cert(@ca, @rsa1, 1, [], nil, nil,
                      not_before: now, not_after: now+3600)
    assert_equal(now.getutc, cert.not_before)
    assert_equal((now+3600).getutc, cert.not_after)

    now = Time.at(0)
    cert = issue_cert(@ca, @rsa1, 1, [], nil, nil,
                      not_before: now, not_after: now)
    assert_equal(now.getutc, cert.not_before)
    assert_equal(now.getutc, cert.not_after)

    now = Time.at(0x7fffffff)
    cert = issue_cert(@ca, @rsa1, 1, [], nil, nil,
                      not_before: now, not_after: now)
    assert_equal(now.getutc, cert.not_before)
    assert_equal(now.getutc, cert.not_after)
  end

  def test_extension_factory
    ca_exts = [
      ["basicConstraints","CA:TRUE",true],
      ["keyUsage","keyCertSign, cRLSign",true],
      ["subjectKeyIdentifier","hash",false],
      ["authorityKeyIdentifier","issuer:always,keyid:always",false],
    ]
    ca_cert = issue_cert(@ca, @rsa1, 1, ca_exts, nil, nil)
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
    ]
    ee1_cert = issue_cert(@ee1, @rsa2, 2, ee1_exts, ca_cert, @rsa1)
    assert_equal(ca_cert.subject.to_der, ee1_cert.issuer.to_der)
    ee1_cert.extensions.each_with_index{|ext, i|
      assert_equal(ee1_exts[i].first, ext.oid)
      assert_equal(ee1_exts[i].last, ext.critical?)
    }
  end

  def test_akiski
    ca_cert = generate_cert(@ca, @rsa1, 4, nil)
    ef = OpenSSL::X509::ExtensionFactory.new(ca_cert, ca_cert)
    ca_cert.add_extension(
      ef.create_extension("subjectKeyIdentifier", "hash", false))
    ca_cert.add_extension(
      ef.create_extension("authorityKeyIdentifier", "issuer:always,keyid:always", false))
    ca_cert.sign(@rsa1, "sha256")

    ca_keyid = get_subject_key_id(ca_cert.to_der, hex: false)
    assert_equal ca_keyid, ca_cert.authority_key_identifier
    assert_equal ca_keyid, ca_cert.subject_key_identifier

    ee_cert = generate_cert(@ee1, @rsa2, 5, ca_cert)
    ef = OpenSSL::X509::ExtensionFactory.new(ca_cert, ee_cert)
    ee_cert.add_extension(
      ef.create_extension("subjectKeyIdentifier", "hash", false))
    ee_cert.add_extension(
      ef.create_extension("authorityKeyIdentifier", "issuer:always,keyid:always", false))
    ee_cert.sign(@rsa1, "sha256")

    ee_keyid = get_subject_key_id(ee_cert.to_der, hex: false)
    assert_equal ca_keyid, ee_cert.authority_key_identifier
    assert_equal ee_keyid, ee_cert.subject_key_identifier
  end

  def test_akiski_missing
    cert = issue_cert(@ee1, @rsa1, 1, [], nil, nil)
    assert_nil(cert.authority_key_identifier)
    assert_nil(cert.subject_key_identifier)
  end

  def test_crl_uris_no_crl_distribution_points
    cert = issue_cert(@ee1, @rsa1, 1, [], nil, nil)
    assert_nil(cert.crl_uris)
  end

  def test_crl_uris
    # Multiple DistributionPoint contains a single general name each
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.config = OpenSSL::Config.parse(<<~_cnf_)
      [crlDistPts]
      URI.1 = http://www.example.com/crl
      URI.2 = ldap://ldap.example.com/cn=ca?certificateRevocationList;binary
    _cnf_
    cdp_cert = generate_cert(@ee1, @rsa1, 3, nil)
    ef.subject_certificate = cdp_cert
    cdp_cert.add_extension(ef.create_extension("crlDistributionPoints", "@crlDistPts"))
    cdp_cert.sign(@rsa1, "sha256")
    assert_equal(
      ["http://www.example.com/crl", "ldap://ldap.example.com/cn=ca?certificateRevocationList;binary"],
      cdp_cert.crl_uris
    )
  end

  def test_crl_uris_multiple_general_names
    # Single DistributionPoint contains multiple general names of type URI
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.config = OpenSSL::Config.parse(<<~_cnf_)
      [crlDistPts_section]
      fullname = URI:http://www.example.com/crl, URI:ldap://ldap.example.com/cn=ca?certificateRevocationList;binary
    _cnf_
    cdp_cert = generate_cert(@ee1, @rsa1, 3, nil)
    ef.subject_certificate = cdp_cert
    cdp_cert.add_extension(ef.create_extension("crlDistributionPoints", "crlDistPts_section"))
    cdp_cert.sign(@rsa1, "sha256")
    assert_equal(
      ["http://www.example.com/crl", "ldap://ldap.example.com/cn=ca?certificateRevocationList;binary"],
      cdp_cert.crl_uris
    )
  end

  def test_crl_uris_no_uris
    # The only DistributionPointName is a directoryName
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.config = OpenSSL::Config.parse(<<~_cnf_)
      [crlDistPts_section]
      fullname = dirName:dirname_section
      [dirname_section]
      CN = dirname
    _cnf_
    cdp_cert = generate_cert(@ee1, @rsa1, 3, nil)
    ef.subject_certificate = cdp_cert
    cdp_cert.add_extension(ef.create_extension("crlDistributionPoints", "crlDistPts_section"))
    cdp_cert.sign(@rsa1, "sha256")
    assert_nil(cdp_cert.crl_uris)
  end

  def test_aia_missing
    cert = issue_cert(@ee1, @rsa1, 1, [], nil, nil)
    assert_nil(cert.ca_issuer_uris)
    assert_nil(cert.ocsp_uris)
  end

  def test_aia
    ef = OpenSSL::X509::ExtensionFactory.new
    aia_cert = generate_cert(@ee1, @rsa1, 4, nil)
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
    aia_cert.sign(@rsa1, "sha256")
    assert_equal(
      ["http://www.example.com/caIssuers", "ldap://ldap.example.com/cn=ca?authorityInfoAccessCaIssuers;binary"],
      aia_cert.ca_issuer_uris
    )
    assert_equal(
      ["http://www.example.com/ocsp", "ldap://ldap.example.com/cn=ca?authorityInfoAccessOcsp;binary"],
      aia_cert.ocsp_uris
    )
  end

  def test_invalid_extension
    integer = OpenSSL::ASN1::Integer.new(0)
    invalid_exts_cert = generate_cert(@ee1, @rsa1, 1, nil)
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

  def test_sign_and_verify
    cert = issue_cert(@ca, @rsa1, 1, [], nil, nil, digest: "SHA256")
    assert_equal("sha256WithRSAEncryption", cert.signature_algorithm) # ln
    assert_equal(true, cert.verify(@rsa1))
    assert_equal(false, cert.verify(@rsa2))
    assert_equal(false, certificate_error_returns_false { cert.verify(@ec1) })
    cert.serial = 2
    assert_equal(false, cert.verify(@rsa1))
  end

  def test_sign_and_verify_nil_digest
    # Ed25519 is not FIPS-approved.
    omit_on_fips
    ed25519 = OpenSSL::PKey::generate_key("ED25519")
    cert = issue_cert(@ca, ed25519, 1, [], nil, nil, digest: nil)
    assert_equal(true, cert.verify(ed25519))
  end

  def test_check_private_key
    cert = issue_cert(@ca, @rsa1, 1, [], nil, nil)
    assert_equal(true, cert.check_private_key(@rsa1))
  end

  def test_read_from_file
    cert = issue_cert(@ca, @rsa1, 1, [], nil, nil)
    Tempfile.create("cert") { |f|
      f << cert.to_pem
      f.rewind
      assert_equal cert.to_der, OpenSSL::X509::Certificate.new(f).to_der
    }
  end

  def test_read_der_then_pem
    cert1 = issue_cert(@ca, @rsa1, 1, [], nil, nil)
    exts = [
      # A new line before PEM block
      ["nsComment", "Another certificate:\n" + cert1.to_pem],
    ]
    cert2 = issue_cert(@ca, @rsa1, 2, exts, nil, nil)

    assert_equal cert2, OpenSSL::X509::Certificate.new(cert2.to_der)
    assert_equal cert2, OpenSSL::X509::Certificate.new(cert2.to_pem)
  end

  def test_eq
    now = Time.now
    cacert = issue_cert(@ca, @rsa1, 1, [], nil, nil,
                        not_before: now, not_after: now + 3600)
    cert1 = issue_cert(@ee1, @rsa2, 2, [], cacert, @rsa1,
                       not_before: now, not_after: now + 3600)
    cert2 = issue_cert(@ee1, @rsa2, 2, [], cacert, @rsa1,
                       not_before: now, not_after: now + 3600)
    cert3 = issue_cert(@ee1, @rsa2, 3, [], cacert, @rsa1,
                       not_before: now, not_after: now + 3600)
    cert4 = issue_cert(@ee1, @rsa2, 2, [], cacert, @rsa1,
                       digest: "sha512", not_before: now, not_after: now + 3600)

    assert_equal false, cert1 == 12345
    assert_equal true, cert1 == cert2
    assert_equal false, cert1 == cert3
    assert_equal false, cert1 == cert4
    assert_equal false, cert3 == cert4
  end

  def test_inspect
    cacert = issue_cert(@ca, @rsa1, 1, [], nil, nil)
    assert_include(cacert.inspect, "subject=#{@ca.inspect}")

    # Do not raise an exception for an invalid certificate
    assert_instance_of(String, OpenSSL::X509::Certificate.new.inspect)
  end

  def test_marshal
    now = Time.now
    cacert = issue_cert(@ca, @rsa1, 1, [], nil, nil,
      not_before: now, not_after: now + 3600)
    cert = issue_cert(@ee1, @rsa2, 2, [], cacert, @rsa1,
      not_before: now, not_after: now + 3600)
    deserialized = Marshal.load(Marshal.dump(cert))

    assert_equal cert.to_der, deserialized.to_der
  end

  def test_load_file_empty_pem
    Tempfile.create("empty.pem") do |f|
      f.close

      assert_raise(OpenSSL::X509::CertificateError) do
        OpenSSL::X509::Certificate.load_file(f.path)
      end
    end
  end

  def test_load_file_fullchain_pem
    cert1 = issue_cert(@ee1, @rsa1, 1, [], nil, nil)
    cert2 = issue_cert(@ca, @rsa2, 1, [], nil, nil)

    Tempfile.create("fullchain.pem") do |f|
      f.puts cert1.to_pem
      f.puts cert2.to_pem
      f.close

      certificates = OpenSSL::X509::Certificate.load_file(f.path)
      assert_equal 2, certificates.size
      assert_equal @ee1, certificates[0].subject
      assert_equal @ca, certificates[1].subject
    end
  end

  def test_load_file_certificate_der
    cert = issue_cert(@ca, @rsa1, 1, [], nil, nil)
    Tempfile.create("certificate.der", binmode: true) do |f|
      f.write cert.to_der
      f.close

      certificates = OpenSSL::X509::Certificate.load_file(f.path)

      # DER encoding can only contain one certificate:
      assert_equal 1, certificates.size
      assert_equal cert.to_der, certificates[0].to_der
    end
  end

  def test_load_file_fullchain_garbage
    Tempfile.create("garbage.txt") do |f|
      f.puts "not a certificate"
      f.close

      assert_raise(OpenSSL::X509::CertificateError) do
        OpenSSL::X509::Certificate.load_file(f.path)
      end
    end
  end

  def test_tbs_precert_bytes
    cert = issue_cert(@ca, @rsa1, 1, [], nil, nil)
    seq = OpenSSL::ASN1.decode(cert.tbs_bytes)

    assert_equal 7, seq.value.size
  end

  private

  def certificate_error_returns_false
    yield
  rescue OpenSSL::X509::CertificateError
    false
  end
end

end
