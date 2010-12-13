require_relative "utils"

if defined?(OpenSSL)

module OpenSSL
  class TestPKCS12 < MiniTest::Unit::TestCase
    include OpenSSL::TestUtils

    def setup
      @mycert = cert
    end

    def test_create
      pkcs12 = OpenSSL::PKCS12.create(
        "omg",
        "hello",
        TEST_KEY_RSA2048,
        @mycert
      )
      assert_equal @mycert, pkcs12.certificate
      assert_equal TEST_KEY_RSA2048, pkcs12.key
      assert_nil pkcs12.ca_certs
    end

    def test_create_no_pass
      pkcs12 = OpenSSL::PKCS12.create(
        nil,
        "hello",
        TEST_KEY_RSA2048,
        @mycert
      )
      assert_equal @mycert, pkcs12.certificate
      assert_equal TEST_KEY_RSA2048, pkcs12.key
      assert_nil pkcs12.ca_certs

      decoded = OpenSSL::PKCS12.new(pkcs12.to_der)
      assert_cert @mycert, decoded.certificate
    end

    def test_create_with_chain
      chain = [cert, cert]

      pkcs12 = OpenSSL::PKCS12.create(
        "omg",
        "hello",
        TEST_KEY_RSA2048,
        @mycert,
        chain
      )
      assert_equal chain, pkcs12.ca_certs
    end

    def test_create_with_bad_nid
      assert_raises(ArgumentError) do
        OpenSSL::PKCS12.create(
          "omg",
          "hello",
          TEST_KEY_RSA2048,
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
        TEST_KEY_RSA2048,
        @mycert,
        [],
        nil,
        nil,
        2048
      )

      assert_raises(TypeError) do
        OpenSSL::PKCS12.create(
          "omg",
          "hello",
          TEST_KEY_RSA2048,
          @mycert,
          [],
          nil,
          nil,
          "omg"
        )
      end
    end

    def test_create_with_mac_itr
      OpenSSL::PKCS12.create(
        "omg",
        "hello",
        TEST_KEY_RSA2048,
        @mycert,
        [],
        nil,
        nil,
        nil,
        2048
      )

      assert_raises(TypeError) do
        OpenSSL::PKCS12.create(
          "omg",
          "hello",
          TEST_KEY_RSA2048,
          @mycert,
          [],
          nil,
          nil,
          nil,
          "omg"
        )
      end
    end

    private
    def assert_cert expected, actual
      [
        :subject,
        :issuer,
        :serial,
        :not_before,
        :not_after,
      ].each do |attribute|
        assert_equal expected.send(attribute), actual.send(attribute)
      end
    end

    def cert
      ca = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=CA")

      now = Time.now
      ca_exts = [
        ["basicConstraints","CA:TRUE",true],
        ["keyUsage","keyCertSign, cRLSign",true],
        ["subjectKeyIdentifier","hash",false],
        ["authorityKeyIdentifier","keyid:always",false],
      ]
      issue_cert(ca, TEST_KEY_RSA2048, 1, now, now+3600, ca_exts,
                            nil, nil, OpenSSL::Digest::SHA1.new)
    end
  end
end

end
