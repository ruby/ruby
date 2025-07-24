# frozen_string_literal: true
require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestPKCS7 < OpenSSL::TestCase
  def setup
    super
    @ca_key = Fixtures.pkey("rsa-1")
    @ee1_key = Fixtures.pkey("rsa-2")
    @ee2_key = Fixtures.pkey("rsa-3")
    ca = OpenSSL::X509::Name.new([["CN", "CA"]])
    ee1 = OpenSSL::X509::Name.new([["CN", "EE1"]])
    ee2 = OpenSSL::X509::Name.new([["CN", "EE2"]])

    ca_exts = [
      ["basicConstraints", "CA:TRUE", true],
      ["keyUsage", "keyCertSign, cRLSign", true],
      ["subjectKeyIdentifier", "hash", false],
      ["authorityKeyIdentifier", "keyid:always", false],
    ]
    @ca_cert = issue_cert(ca, @ca_key, 1, ca_exts, nil, nil)
    ee_exts = [
      ["keyUsage", "nonRepudiation, digitalSignature, keyEncipherment", true],
      ["authorityKeyIdentifier", "keyid:always", false],
      ["extendedKeyUsage", "clientAuth, emailProtection, codeSigning", false],
    ]
    @ee1_cert = issue_cert(ee1, @ee1_key, 2, ee_exts, @ca_cert, @ca_key)
    @ee2_cert = issue_cert(ee2, @ee2_key, 3, ee_exts, @ca_cert, @ca_key)
  end

  def test_signed
    store = OpenSSL::X509::Store.new
    store.add_cert(@ca_cert)

    data = "aaaaa\nbbbbb\nccccc\n"
    ca_certs = [@ca_cert]
    tmp = OpenSSL::PKCS7.sign(@ee1_cert, @ee1_key, data, ca_certs)
    # TODO: #data contains untranslated content
    assert_equal("aaaaa\nbbbbb\nccccc\n", tmp.data)
    assert_nil(tmp.error_string)

    p7 = OpenSSL::PKCS7.new(tmp.to_der)
    assert_nil(p7.data)
    assert_nil(p7.error_string)

    assert_true(p7.verify([], store))
    # AWS-LC does not appear to convert to CRLF automatically
    assert_equal("aaaaa\r\nbbbbb\r\nccccc\r\n", p7.data) unless aws_lc?
    assert_nil(p7.error_string)

    certs = p7.certificates
    assert_equal(2, certs.size)
    assert_equal(@ee1_cert.subject, certs[0].subject)
    assert_equal(@ca_cert.subject, certs[1].subject)

    signers = p7.signers
    assert_equal(1, signers.size)
    assert_equal(@ee1_cert.serial, signers[0].serial)
    assert_equal(@ee1_cert.issuer, signers[0].issuer)
    # AWS-LC does not generate authenticatedAttributes
    assert_in_delta(Time.now, signers[0].signed_time, 10) unless aws_lc?

    assert_false(p7.verify([@ca_cert], OpenSSL::X509::Store.new))
  end

  def test_signed_flags
    store = OpenSSL::X509::Store.new
    store.add_cert(@ca_cert)

    # Normally OpenSSL tries to translate the supplied content into canonical
    # MIME format (e.g. a newline character is converted into CR+LF).
    # If the content is a binary, PKCS7::BINARY flag should be used.
    #
    # PKCS7::NOATTR flag suppresses authenticatedAttributes.
    data = "aaaaa\nbbbbb\nccccc\n"
    flag = OpenSSL::PKCS7::BINARY | OpenSSL::PKCS7::NOATTR
    tmp = OpenSSL::PKCS7.sign(@ee1_cert, @ee1_key, data, [@ca_cert], flag)
    p7 = OpenSSL::PKCS7.new(tmp.to_der)

    assert_true(p7.verify([], store))
    assert_equal(data, p7.data)

    certs = p7.certificates
    assert_equal(2, certs.size)
    assert_equal(@ee1_cert.subject, certs[0].subject)
    assert_equal(@ca_cert.subject, certs[1].subject)

    signers = p7.signers
    assert_equal(1, signers.size)
    assert_equal(@ee1_cert.serial, signers[0].serial)
    assert_equal(@ee1_cert.issuer, signers[0].issuer)
    assert_raise(OpenSSL::PKCS7::PKCS7Error) { signers[0].signed_time }
  end

  def test_signed_multiple_signers
    store = OpenSSL::X509::Store.new
    store.add_cert(@ca_cert)

    # A signed-data which have multiple signatures can be created
    # through the following steps.
    #   1. create two signed-data
    #   2. copy signerInfo and certificate from one to another
    data = "aaaaa\r\nbbbbb\r\nccccc\r\n"
    tmp1 = OpenSSL::PKCS7.sign(@ee1_cert, @ee1_key, data)
    tmp2 = OpenSSL::PKCS7.sign(@ee2_cert, @ee2_key, data)
    tmp1.add_signer(tmp2.signers[0])
    tmp1.add_certificate(@ee2_cert)

    p7 = OpenSSL::PKCS7.new(tmp1.to_der)
    assert_true(p7.verify([], store))
    assert_equal(data, p7.data)

    certs = p7.certificates
    assert_equal(2, certs.size)

    signers = p7.signers
    assert_equal(2, signers.size)
    assert_equal(@ee1_cert.serial, signers[0].serial)
    assert_equal(@ee1_cert.issuer, signers[0].issuer)
    assert_equal(@ee2_cert.serial, signers[1].serial)
    assert_equal(@ee2_cert.issuer, signers[1].issuer)
  end

  def test_signed_add_signer
    data = "aaaaa\nbbbbb\nccccc\n"
    psi = OpenSSL::PKCS7::SignerInfo.new(@ee1_cert, @ee1_key, "sha256")
    p7 = OpenSSL::PKCS7.new
    p7.type = :signed
    p7.add_signer(psi)
    p7.add_certificate(@ee1_cert)
    p7.add_certificate(@ca_cert)
    p7.add_data(data)

    store = OpenSSL::X509::Store.new
    store.add_cert(@ca_cert)

    assert_equal(true, p7.verify([], store))
    assert_equal(true, OpenSSL::PKCS7.new(p7.to_der).verify([], store))
    assert_equal(1, p7.signers.size)
  end

  def test_detached_sign
    store = OpenSSL::X509::Store.new
    store.add_cert(@ca_cert)

    data = "aaaaa\nbbbbb\nccccc\n"
    ca_certs = [@ca_cert]
    flag = OpenSSL::PKCS7::BINARY|OpenSSL::PKCS7::DETACHED
    tmp = OpenSSL::PKCS7.sign(@ee1_cert, @ee1_key, data, ca_certs, flag)
    p7 = OpenSSL::PKCS7.new(tmp.to_der)
    assert_predicate(p7, :detached?)
    assert_true(p7.detached)

    assert_false(p7.verify([], store))
    # FIXME: Should it be nil?
    assert_equal("", p7.data)
    assert_match(/no content|NO_CONTENT/, p7.error_string)

    assert_true(p7.verify([], store, data))
    assert_equal(data, p7.data)
    assert_nil(p7.error_string)

    certs = p7.certificates
    assert_equal(2, certs.size)
    assert_equal(@ee1_cert.subject, certs[0].subject)
    assert_equal(@ca_cert.subject, certs[1].subject)

    signers = p7.signers
    assert_equal(1, signers.size)
    assert_equal(@ee1_cert.serial, signers[0].serial)
    assert_equal(@ee1_cert.issuer, signers[0].issuer)
  end

  def test_signed_authenticated_attributes
    # Using static PEM data because AWS-LC does not support generating one
    # with authenticatedAttributes.
    #
    # p7 was generated with OpenSSL 3.4.1 with this program with commandline
    # "faketime 2025-04-03Z ruby prog.rb":
    #
    #   require_relative "test/openssl/utils"
    #   include OpenSSL::TestUtils
    #   key = Fixtures.pkey("p256")
    #   cert = issue_cert(OpenSSL::X509::Name.new([["CN", "cert"]]), key, 1, [], nil, nil)
    #   p7 = OpenSSL::PKCS7.sign(cert, key, "content", [])
    #   puts p7.to_pem
    p7 = OpenSSL::PKCS7.new(<<~EOF)
-----BEGIN PKCS7-----
MIICvgYJKoZIhvcNAQcCoIICrzCCAqsCAQExDzANBglghkgBZQMEAgEFADAWBgkq
hkiG9w0BBwGgCQQHY29udGVudKCCAQ4wggEKMIGxoAMCAQICAQEwCgYIKoZIzj0E
AwIwDzENMAsGA1UEAwwEY2VydDAeFw0yNTA0MDIyMzAwMDFaFw0yNTA0MDMwMTAw
MDFaMA8xDTALBgNVBAMMBGNlcnQwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAQW
CWTZz6hVQgpDrh5kb1uEs09YHuVJn8CsrjV4bLnADNT/QbnVe20J4FSX4xqFm2f1
87Ukp0XiomZLf11eekQ2MAoGCCqGSM49BAMCA0gAMEUCIEg1fDI8b3hZAArgniVk
HeM6puwgcMh5NXwvJ9x0unVmAiEAppecVTSQ+yEPyBG415Og6sK+RC78pcByEC81
C/QSwRYxggFpMIIBZQIBATAUMA8xDTALBgNVBAMMBGNlcnQCAQEwDQYJYIZIAWUD
BAIBBQCggeQwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
DxcNMjUwNDAzMDAwMDAxWjAvBgkqhkiG9w0BCQQxIgQg7XACtDnprIRfIjV9gius
FERzD722AW0+yUMil7nsn3MweQYJKoZIhvcNAQkPMWwwajALBglghkgBZQMEASow
CwYJYIZIAWUDBAEWMAsGCWCGSAFlAwQBAjAKBggqhkiG9w0DBzAOBggqhkiG9w0D
AgICAIAwDQYIKoZIhvcNAwICAUAwBwYFKw4DAgcwDQYIKoZIhvcNAwICASgwCgYI
KoZIzj0EAwIESDBGAiEAssymc28HySAhg+XeWIpSbtzkwycr2JG6dzHRZ+vn0ocC
IQCJVpo1FTLZOHSc9UpjS+VKR4cg50Iz0HiPyo6hwjCrwA==
-----END PKCS7-----
    EOF

    cert = p7.certificates[0]
    store = OpenSSL::X509::Store.new.tap { |store|
      store.time = Time.utc(2025, 4, 3)
      store.add_cert(cert)
    }
    assert_equal(true, p7.verify([], store))
    assert_equal(1, p7.signers.size)
    signer = p7.signers[0]
    assert_in_delta(Time.utc(2025, 4, 3), signer.signed_time, 10)
  end

  def test_enveloped
    omit_on_fips # PKCS #1 v1.5 padding

    certs = [@ee1_cert, @ee2_cert]
    cipher = OpenSSL::Cipher::AES.new("128-CBC")
    data = "aaaaa\nbbbbb\nccccc\n"

    tmp = OpenSSL::PKCS7.encrypt(certs, data, cipher, OpenSSL::PKCS7::BINARY)
    p7 = OpenSSL::PKCS7.new(tmp.to_der)
    recip = p7.recipients
    assert_equal(:enveloped, p7.type)
    assert_equal(2, recip.size)

    assert_equal(@ca_cert.subject, recip[0].issuer)
    assert_equal(@ee1_cert.serial, recip[0].serial)
    assert_equal(16, @ee1_key.decrypt(recip[0].enc_key).size)
    assert_equal(data, p7.decrypt(@ee1_key, @ee1_cert))

    assert_equal(@ca_cert.subject, recip[1].issuer)
    assert_equal(@ee2_cert.serial, recip[1].serial)
    assert_equal(data, p7.decrypt(@ee2_key, @ee2_cert))

    assert_equal(data, p7.decrypt(@ee1_key))

    assert_raise(OpenSSL::PKCS7::PKCS7Error) {
      p7.decrypt(@ca_key, @ca_cert)
    }

    # Default cipher has been removed in v3.3
    assert_raise_with_message(ArgumentError, /RC2-40-CBC/) {
      OpenSSL::PKCS7.encrypt(certs, data)
    }
  end

  def test_data
    asn1 = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::ObjectId("pkcs7-data"),
      OpenSSL::ASN1::OctetString("content", 0, :EXPLICIT),
    ])
    p7 = OpenSSL::PKCS7.new
    p7.type = :data
    p7.data = "content"
    assert_raise(OpenSSL::PKCS7::PKCS7Error) { p7.add_certificate(@ee1_cert) }
    assert_raise(OpenSSL::PKCS7::PKCS7Error) { p7.certificates = [@ee1_cert] }
    assert_raise(OpenSSL::PKCS7::PKCS7Error) { p7.cipher = "aes-128-cbc" }
    assert_equal(asn1.to_der, p7.to_der)

    p7 = OpenSSL::PKCS7.new(asn1)
    assert_equal(:data, p7.type)
    assert_equal(false, p7.detached?)
    # Not applicable
    assert_nil(p7.certificates)
    assert_nil(p7.crls)
    # Not applicable. Should they return nil or raise an exception instead?
    assert_equal([], p7.signers)
    assert_equal([], p7.recipients)
    # PKCS7#verify can't distinguish verification failure and other errors
    store = OpenSSL::X509::Store.new
    assert_equal(false, p7.verify([@ee1_cert], store))
    assert_match(/wrong content type|WRONG_CONTENT_TYPE/, p7.error_string)
    assert_raise(OpenSSL::PKCS7::PKCS7Error) { p7.decrypt(@ee1_key) }
  end

  def test_empty_signed_data_ruby_bug_19974
    data = "-----BEGIN PKCS7-----\nMAsGCSqGSIb3DQEHAg==\n-----END PKCS7-----\n"
    assert_raise(ArgumentError) { OpenSSL::PKCS7.new(data) }

    data = <<END
MIME-Version: 1.0
Content-Disposition: attachment; filename="smime.p7m"
Content-Type: application/x-pkcs7-mime; smime-type=signed-data; name="smime.p7m"
Content-Transfer-Encoding: base64

#{data}
END
    assert_raise(OpenSSL::PKCS7::PKCS7Error) { OpenSSL::PKCS7.read_smime(data) }
  end

  def test_graceful_parsing_failure #[ruby-core:43250]
    contents = "not a valid PKCS #7 PEM block"
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
    pend "AWS-LC has no current support for SMIME with PKCS7" if aws_lc?

    store = OpenSSL::X509::Store.new
    store.add_cert(@ca_cert)
    ca_certs = [@ca_cert]

    data = "aaaaa\r\nbbbbb\r\nccccc\r\n"
    tmp = OpenSSL::PKCS7.sign(@ee1_cert, @ee1_key, data, ca_certs)
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

  def test_to_text
    omit "AWS-LC does not support PKCS7.to_text" if aws_lc?

    p7 = OpenSSL::PKCS7.new
    p7.type = "signed"
    assert_match(/signed/, p7.to_text)
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

  def test_decode_ber_constructed_string
    omit_on_fips # PKCS #1 v1.5 padding

    p7 = OpenSSL::PKCS7.encrypt([@ee1_cert], "content", "aes-128-cbc")

    # Make an equivalent BER to p7.to_der. Here we convert the encryptedContent
    # field of EncryptedContentInfo into a constructed encoding using the
    # indefinite length form.
    # See https://www.rfc-editor.org/rfc/rfc2315#section-10.1
    asn1 = OpenSSL::ASN1.decode(p7.to_der)
    asn1.indefinite_length = true
    enveloped_data_explicit_tag = asn1.value[1]
    enveloped_data_explicit_tag.indefinite_length = true
    enveloped_data = enveloped_data_explicit_tag.value[0]
    enveloped_data.indefinite_length = true
    encrypted_content_info = enveloped_data.value[2]
    encrypted_content_info.indefinite_length = true
    orig = encrypted_content_info.value[2]
    encrypted_content_info.value[2] = OpenSSL::ASN1::ASN1Data.new([
      OpenSSL::ASN1::OctetString(orig.value[...5]),
      OpenSSL::ASN1::OctetString(orig.value[5...]),
    ], 0, :CONTEXT_SPECIFIC).tap { |x| x.indefinite_length = true }

    assert_not_equal(p7.to_der, asn1.to_der)
    assert_equal(p7.to_der, OpenSSL::PKCS7.new(asn1.to_der).to_der)

    assert_equal("content", OpenSSL::PKCS7.new(p7.to_der).decrypt(@ee1_key))
    assert_equal("content", OpenSSL::PKCS7.new(asn1.to_der).decrypt(@ee1_key))
  end
end

end
