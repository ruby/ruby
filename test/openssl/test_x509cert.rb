begin
  require "openssl"
  require File.join(File.dirname(__FILE__), "utils.rb")
rescue LoadError
end
require "test/unit"

if defined?(OpenSSL)

class OpenSSL::TestX509Certificate < Test::Unit::TestCase
  def setup
    @rsa1024 = OpenSSL::TestUtils::TEST_KEY_RSA1024
    @rsa2048 = OpenSSL::TestUtils::TEST_KEY_RSA2048
    @dsa256  = OpenSSL::TestUtils::TEST_KEY_DSA256
    @dsa512  = OpenSSL::TestUtils::TEST_KEY_DSA512
    @ca = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=CA")
    @ee1 = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=EE1")
    @ee2 = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=EE2")
  end

  def teardown
  end

  def issue_cert(*args)
    OpenSSL::TestUtils.issue_cert(*args)
  end

  def test_serial
    [1, 2**32, 2**100].each{|s|
      cert = issue_cert(@ca, @rsa2048, s, Time.now, Time.now+3600, [],
                        nil, nil, OpenSSL::Digest::SHA1.new)
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
    dss1 = OpenSSL::Digest::DSS1.new
    [
      [@rsa1024, sha1], [@rsa2048, sha1], [@dsa256, dss1], [@dsa512, dss1],
    ].each{|pk, digest|
      cert = issue_cert(@ca, pk, 1, Time.now, Time.now+3600, exts,
                        nil, nil, digest)
      assert_equal(cert.extensions[1].value,
                   OpenSSL::TestUtils.get_subject_key_id(cert))
      cert = OpenSSL::X509::Certificate.new(cert.to_der)
      assert_equal(cert.extensions[1].value,
                   OpenSSL::TestUtils.get_subject_key_id(cert))
    }
  end

  def test_validity
    now = Time.now until now && now.usec != 0
    cert = issue_cert(@ca, @rsa2048, 1, now, now+3600, [],
                      nil, nil, OpenSSL::Digest::SHA1.new)
    assert_not_equal(now, cert.not_before)
    assert_not_equal(now+3600, cert.not_after)

    now = Time.at(now.to_i)
    cert = issue_cert(@ca, @rsa2048, 1, now, now+3600, [],
                      nil, nil, OpenSSL::Digest::SHA1.new)
    assert_equal(now.getutc, cert.not_before)
    assert_equal((now+3600).getutc, cert.not_after)

    now = Time.at(0)
    cert = issue_cert(@ca, @rsa2048, 1, now, now, [],
                      nil, nil, OpenSSL::Digest::SHA1.new)
    assert_equal(now.getutc, cert.not_before)
    assert_equal(now.getutc, cert.not_after)

    now = Time.at(0x7fffffff)
    cert = issue_cert(@ca, @rsa2048, 1, now, now, [],
                      nil, nil, OpenSSL::Digest::SHA1.new)
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
    ca_cert = issue_cert(@ca, @rsa2048, 1, Time.now, Time.now+3600, ca_exts,
                         nil, nil, OpenSSL::Digest::SHA1.new)
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
    ee1_cert = issue_cert(@ee1, @rsa1024, 2, Time.now, Time.now+1800, ee1_exts,
                          ca_cert, @rsa2048, OpenSSL::Digest::SHA1.new)
    assert_equal(ca_cert.subject.to_der, ee1_cert.issuer.to_der)
    ee1_cert.extensions.each_with_index{|ext, i|
      assert_equal(ee1_exts[i].first, ext.oid)
      assert_equal(ee1_exts[i].last, ext.critical?)
    }

    ee2_exts = [
      ["keyUsage","Non Repudiation, Digital Signature, Key Encipherment",true],
      ["subjectKeyIdentifier","hash",false],
      ["authorityKeyIdentifier","issuer:always",false],
      ["extendedKeyUsage","clientAuth, emailProtection, codeSigning",false],
      ["subjectAltName","email:ee2@ruby-lang.org",false],
    ]
    ee2_cert = issue_cert(@ee2, @rsa1024, 3, Time.now, Time.now+1800, ee2_exts,
                          ca_cert, @rsa2048, OpenSSL::Digest::MD5.new)
    assert_equal(ca_cert.subject.to_der, ee2_cert.issuer.to_der)
    ee2_cert.extensions.each_with_index{|ext, i|
      assert_equal(ee2_exts[i].first, ext.oid)
      assert_equal(ee2_exts[i].last, ext.critical?)
    }

  end

  def test_sign_and_verify_wrong_key_type
    cert_rsa = issue_cert(@ca, @rsa2048, 1, Time.now, Time.now+3600, [],
                      nil, nil, OpenSSL::Digest::SHA1.new)
    cert_dsa = issue_cert(@ca, @dsa512, 1, Time.now, Time.now+3600, [],
                      nil, nil, OpenSSL::Digest::DSS1.new)
    begin
      assert_equal(false, cert_rsa.verify(@dsa256))
    rescue OpenSSL::X509::CertificateError => e
      # OpenSSL 1.0.0 added checks for pkey OID
      assert_equal('wrong public key type', e.message)
    end

    begin
      assert_equal(false, cert_dsa.verify(@rsa1024))
    rescue OpenSSL::X509::CertificateError => e
      # OpenSSL 1.0.0 added checks for pkey OID
      assert_equal('wrong public key type', e.message)
    end
  end

  def test_sign_and_verify
    cert = issue_cert(@ca, @rsa2048, 1, Time.now, Time.now+3600, [],
                      nil, nil, OpenSSL::Digest::SHA1.new)
    assert_equal("sha1WithRSAEncryption", cert.signature_algorithm)
    assert_equal(false, cert.verify(@rsa1024))
    assert_equal(true,  cert.verify(@rsa2048))
    cert.serial = 2
    assert_equal(false, cert.verify(@rsa2048))

    cert = issue_cert(@ca, @rsa2048, 1, Time.now, Time.now+3600, [],
                      nil, nil, OpenSSL::Digest::MD5.new)
    assert_equal("md5WithRSAEncryption", cert.signature_algorithm)
    assert_equal(false, cert.verify(@rsa1024))
    assert_equal(true,  cert.verify(@rsa2048))
    cert.subject = @ee1
    assert_equal(false, cert.verify(@rsa2048))

    cert = issue_cert(@ca, @dsa512, 1, Time.now, Time.now+3600, [],
                      nil, nil, OpenSSL::Digest::DSS1.new)
    assert_equal("dsaWithSHA1", cert.signature_algorithm)
    assert_equal(false, cert.verify(@dsa256))
    assert_equal(true,  cert.verify(@dsa512))
    cert.not_after = Time.now
    assert_equal(false, cert.verify(@dsa512))

    assert_raise(OpenSSL::X509::CertificateError){
      cert = issue_cert(@ca, @rsa2048, 1, Time.now, Time.now+3600, [],
                        nil, nil, OpenSSL::Digest::DSS1.new)
    }
    assert_raise(OpenSSL::X509::CertificateError){
      cert = issue_cert(@ca, @dsa512, 1, Time.now, Time.now+3600, [],
                        nil, nil, OpenSSL::Digest::MD5.new)
    }
  end

  def test_dsig_algorithm_mismatch
    assert_raise(OpenSSL::X509::CertificateError) do
      cert = issue_cert(@ca, @rsa2048, 1, Time.now, Time.now+3600, [],
                        nil, nil, OpenSSL::Digest::DSS1.new)
    end
    assert_raise(OpenSSL::X509::CertificateError) do
      cert = issue_cert(@ca, @dsa512, 1, Time.now, Time.now+3600, [],
                        nil, nil, OpenSSL::Digest::MD5.new)
    end
  end

  def test_dsa_with_sha2
    begin
      cert = issue_cert(@ca, @dsa256, 1, Time.now, Time.now+3600, [],
                        nil, nil, OpenSSL::Digest::SHA256.new)
      assert_equal("dsa_with_SHA256", cert.signature_algorithm)
    rescue OpenSSL::X509::CertificateError
      # dsa_with_sha2 not supported. skip following test.
      return
    end
    # TODO: need more tests for dsa + sha2

    # SHA1 is allowed from OpenSSL 1.0.0 (0.9.8 requireds DSS1)
    cert = issue_cert(@ca, @dsa256, 1, Time.now, Time.now+3600, [],
                      nil, nil, OpenSSL::Digest::SHA1.new)
    assert_equal("dsaWithSHA1", cert.signature_algorithm)
  end

  def test_check_private_key
    cert = issue_cert(@ca, @rsa2048, 1, Time.now, Time.now+3600, [],
                      nil, nil, OpenSSL::Digest::SHA1.new)
    assert_equal(true, cert.check_private_key(@rsa2048))
  end

  def test_to_text
    cert_pem = <<END
-----BEGIN CERTIFICATE-----
MIIC8zCCAdugAwIBAgIBATANBgkqhkiG9w0BAQQFADA9MRMwEQYKCZImiZPyLGQB
GRYDb3JnMRkwFwYKCZImiZPyLGQBGRYJcnVieS1sYW5nMQswCQYDVQQDDAJDQTAe
Fw0wOTA1MjMxNTAzNDNaFw0wOTA1MjMxNjAzNDNaMD0xEzARBgoJkiaJk/IsZAEZ
FgNvcmcxGTAXBgoJkiaJk/IsZAEZFglydWJ5LWxhbmcxCzAJBgNVBAMMAkNBMIIB
IjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuV9ht9J7k4NBs38jOXvvTKY9
gW8nLICSno5EETR1cuF7i4pNs9I1QJGAFAX0BEO4KbzXmuOvfCpD3CU+Slp1enen
fzq/t/e/1IRW0wkJUJUFQign4CtrkJL+P07yx18UjyPlBXb81ApEmAB5mrJVSrWm
qbjs07JbuS4QQGGXLc+Su96DkYKmSNVjBiLxVVSpyZfAY3hD37d60uG+X8xdW5v6
8JkRFIhdGlb6JL8fllf/A/blNwdJOhVr9mESHhwGjwfSeTDPfd8ZLE027E5lyAVX
9KZYcU00mOX+fdxOSnGqS/8JDRh0EPHDL15RcJjV2J6vZjPb0rOYGDoMcH+94wID
AQABMA0GCSqGSIb3DQEBBAUAA4IBAQB8UTw1agA9wdXxHMUACduYu6oNL7pdF0dr
w7a4QPJyj62h4+Umxvp13q0PBw0E+mSjhXMcqUhDLjrmMcvvNGhuh5Sdjbe3GI/M
3lCC9OwYYIzzul7omvGC3JEIGfzzdNnPPCPKEWp5X9f0MKLMR79qOf+sjHTjN2BY
SY3YGsEFxyTXDdqrlaYaOtTAdi/C+g1WxR8fkPLefymVwIFwvyc9/bnp7iBn7Hcw
mbxtLPbtQ9mURT0GHewZRTGJ1aiTq9Ag3xXME2FPF04eFRd3mclOQZNXKQ+LDxYf
k0X5FeZvsWf4srFxoVxlcDdJtHh91ZRpDDJYGQlsUm9CPTnO+e4E
-----END CERTIFICATE-----
END

    cert = OpenSSL::X509::Certificate.new(cert_pem)

    cert_text = <<END
  [0]         Version: 3
         SerialNumber: 1
             IssuerDN: DC=org,DC=ruby-lang,CN=CA
           Start Date: Sat May 23 17:03:43 CEST 2009
           Final Date: Sat May 23 18:03:43 CEST 2009
            SubjectDN: DC=org,DC=ruby-lang,CN=CA
           Public Key: RSA Public Key
            modulus: b95f61b7d27b938341b37f23397bef4ca63d816f272c80929e8e4411347572e17b8b8a4db3d2354091801405f40443b829bcd79ae3af7c2a43dc253e4a5a757a77a77f3abfb7f7bfd48456d30909509505422827e02b6b9092fe3f4ef2c75f148f23e50576fcd40a449800799ab2554ab5a6a9b8ecd3b25bb92e104061972dcf92bbde839182a648d5630622f15554a9c997c0637843dfb77ad2e1be5fcc5d5b9bfaf0991114885d1a56fa24bf1f9657ff03f6e53707493a156bf661121e1c068f07d27930cf7ddf192c4d36ec4e65c80557f4a658714d3498e5fe7ddc4e4a71aa4bff090d187410f1c32f5e517098d5d89eaf6633dbd2b398183a0c707fbde3
    public exponent: 10001

  Signature Algorithm: MD5withRSA
            Signature: 7c513c356a003dc1d5f11cc50009db98bbaa0d2f
                       ba5d17476bc3b6b840f2728fada1e3e526c6fa75
                       dead0f070d04fa64a385731ca948432e3ae631cb
                       ef34686e87949d8db7b7188fccde5082f4ec1860
                       8cf3ba5ee89af182dc910819fcf374d9cf3c23ca
                       116a795fd7f430a2cc47bf6a39ffac8c74e33760
                       58498dd81ac105c724d70ddaab95a61a3ad4c076
                       2fc2fa0d56c51f1f90f2de7f2995c08170bf273d
                       fdb9e9ee2067ec773099bc6d2cf6ed43d994453d
                       061dec19453189d5a893abd020df15cc13614f17
                       4e1e15177799c94e419357290f8b0f161f9345f9
                       15e66fb167f8b2b171a15c65703749b4787dd594
                       690c325819096c526f423d39cef9ee04
END
    assert_not_nil(cert.to_text)
    # This is commented out because it doesn't take timezone into consideration; FIXME
    #assert_equal(cert_text, cert.to_text)
  end
end

end
