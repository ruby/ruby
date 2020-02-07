# frozen_string_literal: true
require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestPKCS7 < OpenSSL::TestCase
  def setup
    super
    @rsa1024 = Fixtures.pkey("rsa1024")
    @rsa2048 = Fixtures.pkey("rsa2048")
    ca = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=CA")
    ee1 = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=EE1")
    ee2 = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=EE2")

    ca_exts = [
      ["basicConstraints","CA:TRUE",true],
      ["keyUsage","keyCertSign, cRLSign",true],
      ["subjectKeyIdentifier","hash",false],
      ["authorityKeyIdentifier","keyid:always",false],
    ]
    @ca_cert = issue_cert(ca, @rsa2048, 1, ca_exts, nil, nil)
    ee_exts = [
      ["keyUsage","Non Repudiation, Digital Signature, Key Encipherment",true],
      ["authorityKeyIdentifier","keyid:always",false],
      ["extendedKeyUsage","clientAuth, emailProtection, codeSigning",false],
    ]
    @ee1_cert = issue_cert(ee1, @rsa1024, 2, ee_exts, @ca_cert, @rsa2048)
    @ee2_cert = issue_cert(ee2, @rsa1024, 3, ee_exts, @ca_cert, @rsa2048)
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

    # Normally OpenSSL tries to translate the supplied content into canonical
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

    assert_equal(data, p7.decrypt(@rsa1024))
  end

  def test_graceful_parsing_failure #[ruby-core:43250]
    contents = File.read(__FILE__)
    assert_raise(ArgumentError) { OpenSSL::PKCS7.new(contents) }
  end

  def test_set_type_signed
    p7 = OpenSSL::PKCS7.new
    p7.type = "signed"
    assert_equal(:signed, p7.type)
  end

  def test_set_type_data
    p7 = OpenSSL::PKCS7.new
    p7.type = "data"
    assert_equal(:data, p7.type)
  end

  def test_set_type_signed_and_enveloped
    p7 = OpenSSL::PKCS7.new
    p7.type = "signedAndEnveloped"
    assert_equal(:signedAndEnveloped, p7.type)
  end

  def test_set_type_enveloped
    p7 = OpenSSL::PKCS7.new
    p7.type = "enveloped"
    assert_equal(:enveloped, p7.type)
  end

  def test_set_type_encrypted
    p7 = OpenSSL::PKCS7.new
    p7.type = "encrypted"
    assert_equal(:encrypted, p7.type)
  end

  def test_smime
    store = OpenSSL::X509::Store.new
    store.add_cert(@ca_cert)
    ca_certs = [@ca_cert]

    data = "aaaaa\r\nbbbbb\r\nccccc\r\n"
    tmp = OpenSSL::PKCS7.sign(@ee1_cert, @rsa1024, data, ca_certs)
    p7 = OpenSSL::PKCS7.new(tmp.to_der)
    smime = OpenSSL::PKCS7.write_smime(p7)
    assert_equal(true, smime.start_with?(<<END))
MIME-Version: 1.0
Content-Disposition: attachment; filename="smime.p7m"
Content-Type: application/x-pkcs7-mime; smime-type=signed-data; name="smime.p7m"
Content-Transfer-Encoding: base64

END
    assert_equal(p7.to_der, OpenSSL::PKCS7.read_smime(smime).to_der)

    smime = OpenSSL::PKCS7.write_smime(p7, nil, 0)
    assert_equal(p7.to_der, OpenSSL::PKCS7.read_smime(smime).to_der)
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

  def test_split_content
     pki_message_pem = <<END
-----BEGIN PKCS7-----
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
-----END PKCS7-----
END
    pki_message_content_pem = <<END
-----BEGIN PKCS7-----
MIIDawYJKoZIhvcNAQcDoIIDXDCCA1gCAQAxggEQMIIBDAIBADB1MHAxEDAOBgNV
BAoMB2V4YW1wbGUxFzAVBgNVBAMMDlRBUk1BQyBST09UIENBMSIwIAYJKoZIhvcN
AQkBFhNzb21lb25lQGV4YW1wbGUub3JnMQswCQYDVQQGEwJVUzESMBAGA1UEBwwJ
VG93biBIYWxsAgFmMA0GCSqGSIb3DQEBAQUABIGAbKV17HvGYRtRRBNz1QLpW763
UedhVj5KXi70o4BJGM04lItAgt6aFC9SruZjpWr1gCYKCaRSAg273DeGTQwsDoZ8
6CPXzBpptYLz0MteQXYYWUaPZT+xmvx4NgDyk9P9MoT7JifsPrtXuzqCRFXhGdu8
d/ru+OWxhHLvKH+bYekwggI9BgkqhkiG9w0BBwEwFAYIKoZIhvcNAwcECBNs2U5m
Msd/gIICGFOnLq/EAc9Nv+HjKR3ZVPSJMq0TImjGf5Mvc3nDgI572Hdo2aku0YXM
6WjSWkpYtxpg7Cqxfl6hPSefLPUnBqlIoM2qbrE7MSKEVD6+2bW9GqYPFVg4qQLL
sOxnxJIMfOvLFfd7guL+iLH424XfiUUxaf8EdZE4u2IEl4REvkS1FoEGwyA4BEGM
SeVPedQCbZ0qY7Pc2tmZE3XfEUhIsyStG0Nb6i6AKcAFYGapbgE6kAB0gwsYcHlW
MOvsvdAfcTq6jwtHlO1s68qtvkWquTQ9lpX+fzddUUNxEHSqv5eU3oo6fT3Vj5ZF
IVlaA5ThZMrI5PgRPuwJM4GL8/VLwY5mbDLFqn/irGeEvP99J3S87ornLLunjpxS
y1/AymcVep2H32Tj82WS/IRQXBOzz4EnQRJGszKxAV6tY+Zje3sWyTTgObhlsiTQ
TDgnvtSW8RvVHqKrwgkxxEsRHg7u8UdzZ0jg+O5+3F8B6/NWMyts0OaFqT9wvI8y
O7VIy3dUtGdz7Hde6Ggp/iTn1LbgdJ3N8Hzxf1j6NMWUKHVsadvwpRJbUeqq9c3+
QuxsJi8wWemxxQCE+tPyc1dP+ej5/M7bERbSOHMGgX03758IvP7A/fy2DjGPv2+l
AwlEke0Uze1367QKgxM0nc3SZDlptY7zPIJC5saWXb8Rt2bw2JxEBOTavrp+ZwJ8
tcH961onq8Tme2ICaCzk
-----END PKCS7-----
END
    pki_msg = OpenSSL::PKCS7.new(pki_message_pem)
    store = OpenSSL::X509::Store.new
    pki_msg.verify(nil, store, nil, OpenSSL::PKCS7::NOVERIFY)
    p7enc = OpenSSL::PKCS7.new(pki_msg.data)
    assert_equal(pki_message_content_pem, p7enc.to_pem)
  end
end

end
