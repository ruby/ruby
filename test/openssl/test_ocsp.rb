require_relative "utils"

if defined?(OpenSSL)

class OpenSSL::TestOCSP < Test::Unit::TestCase
  include OpenSSL::OCSPTestSetup

  def test_new_certificate_id
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert)
    assert_kind_of OpenSSL::OCSP::CertificateId, cid
    assert_equal @cert.serial, cid.serial
  end

  def test_new_certificate_id_with_digest
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA256.new)
    assert_kind_of OpenSSL::OCSP::CertificateId, cid
    assert_equal @cert.serial, cid.serial
  end if defined?(OpenSSL::Digest::SHA256)

  def test_new_ocsp_request
    assert_separately(%w[-ropenssl/utils -], <<-END)
    extend OpenSSL::OCSPTestSetup
    setup
    request = OpenSSL::OCSP::Request.new
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    request.add_certid(cid)
    request.sign(@cert, @key, [@cert])
    assert_kind_of OpenSSL::OCSP::Request, request
    # in current implementation not same instance of certificate id, but should contain same data
    assert_equal cid.serial, request.certid.first.serial
    END
  end
end

end
