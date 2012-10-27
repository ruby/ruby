require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestPKCS7 < Test::Unit::TestCase
  def setup
    @rsa1024 = OpenSSL::TestUtils::TEST_KEY_RSA1024
    @rsa2048 = OpenSSL::TestUtils::TEST_KEY_RSA2048
    ca = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=CA")
    ee1 = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=EE1")
    ee2 = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=EE2")

    now = Time.now
    ca_exts = [
      ["basicConstraints","CA:TRUE",true],
      ["keyUsage","keyCertSign, cRLSign",true],
      ["subjectKeyIdentifier","hash",false],
      ["authorityKeyIdentifier","keyid:always",false],
    ]
    @ca_cert = issue_cert(ca, @rsa2048, 1, now, now+3600, ca_exts,
                           nil, nil, OpenSSL::Digest::SHA1.new)
    ee_exts = [
      ["keyUsage","Non Repudiation, Digital Signature, Key Encipherment",true],
      ["authorityKeyIdentifier","keyid:always",false],
      ["extendedKeyUsage","clientAuth, emailProtection, codeSigning",false],
    ]
    @ee1_cert = issue_cert(ee1, @rsa1024, 2, now, now+1800, ee_exts,
                           @ca_cert, @rsa2048, OpenSSL::Digest::SHA1.new)
    @ee2_cert = issue_cert(ee2, @rsa1024, 3, now, now+1800, ee_exts,
                           @ca_cert, @rsa2048, OpenSSL::Digest::SHA1.new)
  end

  def issue_cert(*args)
    OpenSSL::TestUtils.issue_cert(*args)
  end

  def test_signed
    store = OpenSSL::X509::Store.new
    store.add_cert(@ca_cert)
    ca_certs = [@ca_cert]

    data = "aaaaa\r\nbbbbb\r\nccccc\r\n"
    tmp = OpenSSL::PKCS7.sign(@ee1_cert, @rsa1024, data, ca_certs)
    p7 = OpenSSL::PKCS7.new(tmp.to_der)
    certs = p7.certificates
    signers = p7.signers
    assert(p7.verify([], store))
    assert_equal(data, p7.data)
    assert_equal(2, certs.size)
    assert_equal(@ee1_cert.subject.to_s, certs[0].subject.to_s)
    assert_equal(@ca_cert.subject.to_s, certs[1].subject.to_s)
    assert_equal(1, signers.size)
    assert_equal(@ee1_cert.serial, signers[0].serial)
    assert_equal(@ee1_cert.issuer.to_s, signers[0].issuer.to_s)

    # Normaly OpenSSL tries to translate the supplied content into canonical
    # MIME format (e.g. a newline character is converted into CR+LF).
    # If the content is a binary, PKCS7::BINARY flag should be used.

    data = "aaaaa\nbbbbb\nccccc\n"
    flag = OpenSSL::PKCS7::BINARY
    tmp = OpenSSL::PKCS7.sign(@ee1_cert, @rsa1024, data, ca_certs, flag)
    p7 = OpenSSL::PKCS7.new(tmp.to_der)
    certs = p7.certificates
    signers = p7.signers
    assert(p7.verify([], store))
    assert_equal(data, p7.data)
    assert_equal(2, certs.size)
    assert_equal(@ee1_cert.subject.to_s, certs[0].subject.to_s)
    assert_equal(@ca_cert.subject.to_s, certs[1].subject.to_s)
    assert_equal(1, signers.size)
    assert_equal(@ee1_cert.serial, signers[0].serial)
    assert_equal(@ee1_cert.issuer.to_s, signers[0].issuer.to_s)

    # A signed-data which have multiple signatures can be created
    # through the following steps.
    #   1. create two signed-data
    #   2. copy signerInfo and certificate from one to another

    tmp1 = OpenSSL::PKCS7.sign(@ee1_cert, @rsa1024, data, [], flag)
    tmp2 = OpenSSL::PKCS7.sign(@ee2_cert, @rsa1024, data, [], flag)
    tmp1.add_signer(tmp2.signers[0])
    tmp1.add_certificate(@ee2_cert)

    p7 = OpenSSL::PKCS7.new(tmp1.to_der)
    certs = p7.certificates
    signers = p7.signers
    assert(p7.verify([], store))
    assert_equal(data, p7.data)
    assert_equal(2, certs.size)
    assert_equal(2, signers.size)
    assert_equal(@ee1_cert.serial, signers[0].serial)
    assert_equal(@ee1_cert.issuer.to_s, signers[0].issuer.to_s)
    assert_equal(@ee2_cert.serial, signers[1].serial)
    assert_equal(@ee2_cert.issuer.to_s, signers[1].issuer.to_s)
  end

  def test_detached_sign
    store = OpenSSL::X509::Store.new
    store.add_cert(@ca_cert)
    ca_certs = [@ca_cert]

    data = "aaaaa\nbbbbb\nccccc\n"
    flag = OpenSSL::PKCS7::BINARY|OpenSSL::PKCS7::DETACHED
    tmp = OpenSSL::PKCS7.sign(@ee1_cert, @rsa1024, data, ca_certs, flag)
    p7 = OpenSSL::PKCS7.new(tmp.to_der)
    assert_nothing_raised do
      OpenSSL::ASN1.decode(p7)
    end

    certs = p7.certificates
    signers = p7.signers
    assert(!p7.verify([], store))
    assert(p7.verify([], store, data))
    assert_equal(data, p7.data)
    assert_equal(2, certs.size)
    assert_equal(@ee1_cert.subject.to_s, certs[0].subject.to_s)
    assert_equal(@ca_cert.subject.to_s, certs[1].subject.to_s)
    assert_equal(1, signers.size)
    assert_equal(@ee1_cert.serial, signers[0].serial)
    assert_equal(@ee1_cert.issuer.to_s, signers[0].issuer.to_s)
  end

  def test_enveloped
    if OpenSSL::OPENSSL_VERSION_NUMBER <= 0x0090704f
      # PKCS7_encrypt() of OpenSSL-0.9.7d goes to SEGV.
      # http://www.mail-archive.com/openssl-dev@openssl.org/msg17376.html
      return
    end

    certs = [@ee1_cert, @ee2_cert]
    cipher = OpenSSL::Cipher::AES.new("128-CBC")
    data = "aaaaa\nbbbbb\nccccc\n"

    tmp = OpenSSL::PKCS7.encrypt(certs, data, cipher, OpenSSL::PKCS7::BINARY)
    p7 = OpenSSL::PKCS7.new(tmp.to_der)
    recip = p7.recipients
    assert_equal(:enveloped, p7.type)
    assert_equal(2, recip.size)

    assert_equal(@ca_cert.subject.to_s, recip[0].issuer.to_s)
    assert_equal(2, recip[0].serial)
    assert_equal(data, p7.decrypt(@rsa1024, @ee1_cert))

    assert_equal(@ca_cert.subject.to_s, recip[1].issuer.to_s)
    assert_equal(3, recip[1].serial)
    assert_equal(data, p7.decrypt(@rsa1024, @ee2_cert))
  end

  def test_graceful_parsing_failure #[ruby-core:43250]
    contents = File.read(__FILE__)
    assert_raise(ArgumentError) { OpenSSL::PKCS7.new(contents) }
  end

  def test_set_type_signed
    p7 = OpenSSL::PKCS7.new
    p7.type = "signed"
    assert_equal(p7.type, :signed)
  end
  
  def test_set_type_data
    p7 = OpenSSL::PKCS7.new
    p7.type = "data"
    assert_equal(p7.type, :data)
  end
  
  def test_set_type_signed_and_enveloped
    p7 = OpenSSL::PKCS7.new
    p7.type = "signedAndEnveloped"
    assert_equal(p7.type, :signedAndEnveloped)
  end
  
  def test_set_type_enveloped
    p7 = OpenSSL::PKCS7.new
    p7.type = "enveloped"
    assert_equal(p7.type, :enveloped)
  end
  
  def test_set_type_encrypted
    p7 = OpenSSL::PKCS7.new
    p7.type = "encrypted"
    assert_equal(p7.type, :encrypted)
  end

  def test_degenerate_pkcs7
    ca_cert_pem = <<END
-----BEGIN CERTIFICATE-----
MIID4DCCAsigAwIBAgIJAL1oVI72wmQwMA0GCSqGSIb3DQEBBQUAMFMxCzAJBgNV
BAYTAkFVMQ4wDAYDVQQIEwVTdGF0ZTENMAsGA1UEBxMEQ2l0eTEQMA4GA1UEChMH
RXhhbXBsZTETMBEGA1UEAxMKRXhhbXBsZSBDQTAeFw0xMjEwMTgwOTE2NTBaFw0y
MjEwMTYwOTE2NTBaMFMxCzAJBgNVBAYTAkFVMQ4wDAYDVQQIEwVTdGF0ZTENMAsG
A1UEBxMEQ2l0eTEQMA4GA1UEChMHRXhhbXBsZTETMBEGA1UEAxMKRXhhbXBsZSBD
QTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMTSPNxOkd5NN19XO0fJ
tGVlWN4DWuvVL9WbWnXJXX9rU6X8sSOL9RrRA64eEZf2UBFjz9fMHZj/OGcxZpus
4YtzfSrMU6xfvsIHeqX+mT60ms2RfX4UXab50MQArBin3JVKHGnOi25uyAOylVFU
TuzzQJvKyB67vjuRPMlVAgVAZAP07ru9gW0ajt/ODxvUfvXxp5SFF68mVP2ipMBr
4fujUwQC6cVHmnuL6p87VFoo9uk87TSQVDOQGL8MK4moMFtEW9oUTU22CgnxnCsS
sCCELYhy9BdaTWQH26LzMfhnwSuIRHZyprW4WZtU0akrYXNiCj8o92rZmQWXJDbl
qNECAwEAAaOBtjCBszAdBgNVHQ4EFgQUNtVw4jvkZZbkdQbkYi2/F4QN79owgYMG
A1UdIwR8MHqAFDbVcOI75GWW5HUG5GItvxeEDe/aoVekVTBTMQswCQYDVQQGEwJB
VTEOMAwGA1UECBMFU3RhdGUxDTALBgNVBAcTBENpdHkxEDAOBgNVBAoTB0V4YW1w
bGUxEzARBgNVBAMTCkV4YW1wbGUgQ0GCCQC9aFSO9sJkMDAMBgNVHRMEBTADAQH/
MA0GCSqGSIb3DQEBBQUAA4IBAQBvJIsY9bIqliZ3WD1KoN4cvAQeRAPsoLXQkkHg
P6Nrcw9rJ5JvoHfYbo5aNlwbnkbt/B2xlVEXUYpJoBZFXafgxG2gJleioIgnaDS4
FPPwZf1C5ZrOgUBfxTGjHex4ghSAoNGOd35jQzin5NGKOvZclPjZ2vQ++LP3aA2l
9Fn2qASS46IzMGJlC75mlTOTQwDM16UunMAK26lNG9J6q02o4d/oU2a7x0fD80yF
64kNA1wDAwaVCYiUH541qKp+b4iDqer8nf8HqzYDFlpje18xYZMEd1hj8dVOharM
pISJ+D52hV/BGEYF8r5k3hpC5d76gSP2oCcaY0XvLBf97qik
-----END CERTIFICATE-----
END
    p7 = OpenSSL::PKCS7.new
    p7.type = "signed"
    ca_cert = OpenSSL::X509::Certificate.new(ca_cert_pem)
    p7.add_certificate ca_cert
    p7.add_data ""
    
    assert_nothing_raised do
      p7.to_pem
    end
  end
end

end
