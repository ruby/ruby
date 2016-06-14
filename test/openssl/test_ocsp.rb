# frozen_string_literal: false
require_relative "utils"

if defined?(OpenSSL::TestUtils)

class OpenSSL::TestOCSP < OpenSSL::TestCase
  def setup
    ca_subj = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=TestCA")
    ca_key = OpenSSL::TestUtils::TEST_KEY_RSA1024
    ca_serial = 0xabcabcabcabc
    ca_exts = [
      ["basicConstraints", "CA:TRUE", true],
      ["keyUsage", "cRLSign,keyCertSign", true],
    ]

    subj = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=TestCert")
    @key = OpenSSL::TestUtils::TEST_KEY_RSA1024
    serial = 0xabcabcabcabd

    now = Time.at(Time.now.to_i) # suppress usec
    dgst = OpenSSL::Digest::SHA1.new

    @ca_cert = OpenSSL::TestUtils.issue_cert(
       ca_subj, ca_key, ca_serial, now, now+3600, ca_exts, nil, nil, dgst)
    @cert = OpenSSL::TestUtils.issue_cert(
       subj, @key, serial, now, now+3600, [], @ca_cert, ca_key, dgst)

    @key2 = OpenSSL::TestUtils::TEST_KEY_RSA2048
    cert2_exts = [
      ["extendedKeyUsage", "OCSPSigning", true],
    ]
    @cert2 = OpenSSL::TestUtils.issue_cert(
       OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=TestCert2"),
       @key2, serial+1, now, now+3600, cert2_exts, @ca_cert, ca_key, "SHA256")
  end

  def test_new_certificate_id
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert)
    assert_kind_of OpenSSL::OCSP::CertificateId, cid
    assert_equal @cert.serial, cid.serial
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA256.new)
    assert_kind_of OpenSSL::OCSP::CertificateId, cid
    assert_equal @cert.serial, cid.serial
  end

  def test_certificate_id_issuer_name_hash
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert)
    assert_equal OpenSSL::Digest::SHA1.hexdigest(@cert.issuer.to_der), cid.issuer_name_hash
    assert_equal "d91f736ac4dc3242f0fb9b77a3149bd83c5c43d0", cid.issuer_name_hash
  end

  def test_certificate_id_issuer_key_hash
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert)
    assert_equal OpenSSL::Digest::SHA1.hexdigest(OpenSSL::ASN1.decode(@ca_cert.to_der).value[0].value[6].value[1].value), cid.issuer_key_hash
    assert_equal "d1fef9fbf8ae1bc160cbfa03e2596dd873089213", cid.issuer_key_hash
  end

  def test_certificate_id_hash_algorithm
    cid_sha1 = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    cid_sha256 = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA256.new)
    assert_equal "sha1", cid_sha1.hash_algorithm
    assert_equal "sha256", cid_sha256.hash_algorithm
  end

  def test_certificate_id_der
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert) # hash algorithm defaults to SHA-1
    der = cid.to_der
    asn1 = OpenSSL::ASN1.decode(der)
    assert_equal OpenSSL::ASN1.ObjectId("SHA1").to_der, asn1.value[0].value[0].to_der
    assert_equal OpenSSL::Digest::SHA1.digest(@cert.issuer.to_der), asn1.value[1].value
    assert_equal OpenSSL::Digest::SHA1.digest(OpenSSL::ASN1.decode(@ca_cert.to_der).value[0].value[6].value[1].value), asn1.value[2].value
    assert_equal @cert.serial, asn1.value[3].value
    assert_equal der, OpenSSL::OCSP::CertificateId.new(der).to_der
  end

  def test_request_der
    request = OpenSSL::OCSP::Request.new
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    request.add_certid(cid)
    request.sign(@cert, @key, [@ca_cert], 0)
    asn1 = OpenSSL::ASN1.decode(request.to_der)
    assert_equal cid.to_der, asn1.value[0].value.find { |a| a.tag_class == :UNIVERSAL }.value[0].value[0].to_der
    assert_equal OpenSSL::ASN1.ObjectId("sha1WithRSAEncryption").to_der, asn1.value[1].value[0].value[0].value[0].to_der
    assert_equal @cert.to_der, asn1.value[1].value[0].value[2].value[0].value[0].to_der
    assert_equal @ca_cert.to_der, asn1.value[1].value[0].value[2].value[0].value[1].to_der
    assert_equal asn1.to_der, OpenSSL::OCSP::Request.new(asn1.to_der).to_der
  end

  def test_new_ocsp_request
    request = OpenSSL::OCSP::Request.new
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    request.add_certid(cid)
    request.sign(@cert, @key, [@cert])
    assert_kind_of OpenSSL::OCSP::Request, request
    # in current implementation not same instance of certificate id, but should contain same data
    assert_equal cid.serial, request.certid.first.serial
  end

  def test_basic_response_der
    bres = OpenSSL::OCSP::BasicResponse.new
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    bres.add_status(cid, OpenSSL::OCSP::V_CERTSTATUS_GOOD, 0, nil, -300, 500, [])
    bres.add_nonce("NONCE")
    bres.sign(@cert2, @key2, [@ca_cert], 0)
    der = bres.to_der
    asn1 = OpenSSL::ASN1.decode(der)
    assert_equal cid.to_der, asn1.value[0].value.find { |a| a.class == OpenSSL::ASN1::Sequence }.value[0].value[0].to_der
    assert_equal OpenSSL::ASN1.Sequence([@cert2, @ca_cert]).to_der, asn1.value[3].value[0].to_der
    assert_equal der, OpenSSL::OCSP::BasicResponse.new(der).to_der
  end

  def test_response_der
    bres = OpenSSL::OCSP::BasicResponse.new
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    bres.add_status(cid, OpenSSL::OCSP::V_CERTSTATUS_GOOD, 0, nil, -300, 500, [])
    bres.sign(@cert2, @key2, [@ca_cert], 0)
    res = OpenSSL::OCSP::Response.create(OpenSSL::OCSP::RESPONSE_STATUS_SUCCESSFUL, bres)
    der = res.to_der
    asn1 = OpenSSL::ASN1.decode(der)
    assert_equal OpenSSL::OCSP::RESPONSE_STATUS_SUCCESSFUL, asn1.value[0].value
    assert_equal OpenSSL::ASN1.ObjectId("basicOCSPResponse").to_der, asn1.value[1].value[0].value[0].to_der
    assert_equal bres.to_der, asn1.value[1].value[0].value[1].value
    assert_equal der, OpenSSL::OCSP::Response.new(der).to_der
  end
end

end
