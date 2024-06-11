# frozen_string_literal: true
require_relative "utils"

if defined?(OpenSSL)

module OpenSSL
  class TestPKCS12 < OpenSSL::TestCase
    DEFAULT_PBE_PKEYS = "PBE-SHA1-3DES"
    DEFAULT_PBE_CERTS = "PBE-SHA1-3DES"

    def setup
      super
      ca = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=CA")
      ca_exts = [
        ["basicConstraints","CA:TRUE",true],
        ["keyUsage","keyCertSign, cRLSign",true],
        ["subjectKeyIdentifier","hash",false],
        ["authorityKeyIdentifier","keyid:always",false],
      ]
      ca_key = Fixtures.pkey("rsa-1")
      @cacert = issue_cert(ca, ca_key, 1, ca_exts, nil, nil)

      inter_ca = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=Intermediate CA")
      inter_ca_key = Fixtures.pkey("rsa-2")
      @inter_cacert = issue_cert(inter_ca, inter_ca_key, 2, ca_exts, @cacert, ca_key)

      exts = [
        ["keyUsage","digitalSignature",true],
        ["subjectKeyIdentifier","hash",false],
      ]
      ee = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=Ruby PKCS12 Test Certificate")
      @mykey = Fixtures.pkey("rsa-3")
      @mycert = issue_cert(ee, @mykey, 3, exts, @inter_cacert, inter_ca_key)
    end

    def test_create_single_key_single_cert
      pkcs12 = OpenSSL::PKCS12.create(
        "omg",
        "hello",
        @mykey,
        @mycert,
        nil,
        DEFAULT_PBE_PKEYS,
        DEFAULT_PBE_CERTS,
      )
      assert_equal @mycert, pkcs12.certificate
      assert_equal @mykey.to_der, pkcs12.key.to_der
      assert_nil pkcs12.ca_certs

      der = pkcs12.to_der
      decoded = OpenSSL::PKCS12.new(der, "omg")
      assert_equal @mykey.to_der, decoded.key.to_der
      assert_equal @mycert, decoded.certificate
      assert_equal [], Array(decoded.ca_certs)
    end

    def test_create_no_pass
      pkcs12 = OpenSSL::PKCS12.create(
        nil,
        "hello",
        @mykey,
        @mycert,
        nil,
        DEFAULT_PBE_PKEYS,
        DEFAULT_PBE_CERTS,
      )
      assert_equal @mycert, pkcs12.certificate
      assert_equal @mykey.to_der, pkcs12.key.to_der
      assert_nil pkcs12.ca_certs

      decoded = OpenSSL::PKCS12.new(pkcs12.to_der)
      assert_equal @mycert, decoded.certificate
    end

    def test_create_with_chain
      chain = [@inter_cacert, @cacert]

      pkcs12 = OpenSSL::PKCS12.create(
        "omg",
        "hello",
        @mykey,
        @mycert,
        chain,
        DEFAULT_PBE_PKEYS,
        DEFAULT_PBE_CERTS,
      )
      assert_equal chain, pkcs12.ca_certs
    end

    def test_create_with_chain_decode
      chain = [@cacert, @inter_cacert]

      passwd = "omg"

      pkcs12 = OpenSSL::PKCS12.create(
        passwd,
        "hello",
        @mykey,
        @mycert,
        chain,
        DEFAULT_PBE_PKEYS,
        DEFAULT_PBE_CERTS,
      )

      decoded = OpenSSL::PKCS12.new(pkcs12.to_der, passwd)
      assert_equal chain.size, decoded.ca_certs.size
      assert_include decoded.ca_certs, @cacert
      assert_include decoded.ca_certs, @inter_cacert
      assert_equal @mycert, decoded.certificate
      assert_equal @mykey.to_der, decoded.key.to_der
    end

    def test_create_with_bad_nid
      assert_raise(ArgumentError) do
        OpenSSL::PKCS12.create(
          "omg",
          "hello",
          @mykey,
          @mycert,
          [],
          "foo"
        )
      end
    end

    def test_create_with_itr
      OpenSSL::PKCS12.create(
        "omg",
        "hello",
        @mykey,
        @mycert,
        [],
        DEFAULT_PBE_PKEYS,
        DEFAULT_PBE_CERTS,
        2048
      )

      assert_raise(TypeError) do
        OpenSSL::PKCS12.create(
          "omg",
          "hello",
          @mykey,
          @mycert,
          [],
          DEFAULT_PBE_PKEYS,
          DEFAULT_PBE_CERTS,
          "omg"
        )
      end
    end

    def test_create_with_mac_itr
      OpenSSL::PKCS12.create(
        "omg",
        "hello",
        @mykey,
        @mycert,
        [],
        DEFAULT_PBE_PKEYS,
        DEFAULT_PBE_CERTS,
        nil,
        2048
      )

      assert_raise(TypeError) do
        OpenSSL::PKCS12.create(
          "omg",
          "hello",
          @mykey,
          @mycert,
          [],
          DEFAULT_PBE_PKEYS,
          DEFAULT_PBE_CERTS,
          nil,
          "omg"
        )
      end
    end

    def test_create_with_keytype
      OpenSSL::PKCS12.create(
        "omg",
        "hello",
        @mykey,
        @mycert,
        [],
        DEFAULT_PBE_PKEYS,
        DEFAULT_PBE_CERTS,
        nil,
        nil,
        OpenSSL::PKCS12::KEY_SIG
      )

      assert_raise(ArgumentError) do
        OpenSSL::PKCS12.create(
          "omg",
          "hello",
          @mykey,
          @mycert,
          [],
          DEFAULT_PBE_PKEYS,
          DEFAULT_PBE_CERTS,
          nil,
          nil,
          2048
        )
      end
    end

    def test_new_with_no_keys
      # generated with:
      #   openssl pkcs12 -certpbe PBE-SHA1-3DES -in <@mycert> -nokeys -export
      str = <<~EOF.unpack1("m")
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
AA==
      EOF
      p12 = OpenSSL::PKCS12.new(str, "abc123")

      assert_equal nil, p12.key
      assert_equal nil, p12.certificate
      assert_equal 1, p12.ca_certs.size
      assert_equal @mycert.subject, p12.ca_certs[0].subject
    end

    def test_new_with_no_certs
      # generated with:
      #   openssl pkcs12 -inkey fixtures/openssl/pkey/rsa-1.pem -nocerts -export
      str = <<~EOF.unpack1("m")
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
BC8fv38mue8LZVcbHQQIUNrWKEnskCoCAggA
      EOF
      p12 = OpenSSL::PKCS12.new(str, "abc123")

      assert_equal Fixtures.pkey("rsa-1").to_der, p12.key.to_der
      assert_equal nil, p12.certificate
      assert_equal [], Array(p12.ca_certs)
    end

    def test_dup
      p12 = OpenSSL::PKCS12.create(
        "pass",
        "name",
        @mykey,
        @mycert,
        nil,
        DEFAULT_PBE_PKEYS,
        DEFAULT_PBE_CERTS,
      )
      assert_equal p12.to_der, p12.dup.to_der
    end
  end
end

end
