# frozen_string_literal: true
require_relative "utils"

if defined?(OpenSSL)

module OpenSSL
  class TestPKCS12 < OpenSSL::TestCase
    def setup
      super
      ca = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=CA")
      ca_exts = [
        ["basicConstraints","CA:TRUE",true],
        ["keyUsage","keyCertSign, cRLSign",true],
        ["subjectKeyIdentifier","hash",false],
        ["authorityKeyIdentifier","keyid:always",false],
      ]
      @cacert = issue_cert(ca, Fixtures.pkey("rsa2048"), 1, ca_exts, nil, nil)

      inter_ca = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=Intermediate CA")
      inter_ca_key = OpenSSL::PKey.read <<-_EOS_
-----BEGIN RSA PRIVATE KEY-----
MIICXAIBAAKBgQDp7hIG0SFMG/VWv1dBUWziAPrNmkMXJgTCAoB7jffzRtyyN04K
oq/89HAszTMStZoMigQURfokzKsjpUp8OYCAEsBtt9d5zPndWMz/gHN73GrXk3LT
ZsxEn7Xv5Da+Y9F/Hx2QZUHarV5cdZixq2NbzWGwrToogOQMh2pxN3Z/0wIDAQAB
AoGBAJysUyx3olpsGzv3OMRJeahASbmsSKTXVLZvoIefxOINosBFpCIhZccAG6UV
5c/xCvS89xBw8aD15uUfziw3AuT8QPEtHCgfSjeT7aWzBfYswEgOW4XPuWr7EeI9
iNHGD6z+hCN/IQr7FiEBgTp6A+i/hffcSdR83fHWKyb4M7TRAkEA+y4BNd668HmC
G5MPRx25n6LixuBxrNp1umfjEI6UZgEFVpYOg4agNuimN6NqM253kcTR94QNTUs5
Kj3EhG1YWwJBAO5rUjiOyCNVX2WUQrOMYK/c1lU7fvrkdygXkvIGkhsPoNRzLPeA
HGJszKtrKD8bNihWpWNIyqKRHfKVD7yXT+kCQGCAhVCIGTRoypcDghwljHqLnysf
ci0h5ZdPcIqc7ODfxYhFsJ/Rql5ONgYsT5Ig/+lOQAkjf+TRYM4c2xKx2/8CQBvG
jv6dy70qDgIUgqzONtlmHeYyFzn9cdBO5sShdVYHvRHjFSMEXsosqK9zvW2UqvuK
FJx7d3f29gkzynCLJDkCQGQZlEZJC4vWmWJGRKJ24P6MyQn3VsPfErSKOg4lvyM3
Li8JsX5yIiuVYaBg/6ha3tOg4TCa5K/3r3tVliRZ2Es=
-----END RSA PRIVATE KEY-----
      _EOS_
      @inter_cacert = issue_cert(inter_ca, inter_ca_key, 2, ca_exts, @cacert, Fixtures.pkey("rsa2048"))

      exts = [
        ["keyUsage","digitalSignature",true],
        ["subjectKeyIdentifier","hash",false],
      ]
      ee = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=Ruby PKCS12 Test Certificate")
      @mykey = Fixtures.pkey("rsa1024")
      @mycert = issue_cert(ee, @mykey, 3, exts, @inter_cacert, inter_ca_key)
    end

    def test_create
      pkcs12 = OpenSSL::PKCS12.create(
        "omg",
        "hello",
        @mykey,
        @mycert
      )
      assert_equal @mycert.to_der, pkcs12.certificate.to_der
      assert_equal @mykey.to_der, pkcs12.key.to_der
      assert_nil pkcs12.ca_certs
    end

    def test_create_no_pass
      pkcs12 = OpenSSL::PKCS12.create(
        nil,
        "hello",
        @mykey,
        @mycert
      )
      assert_equal @mycert.to_der, pkcs12.certificate.to_der
      assert_equal @mykey.to_der, pkcs12.key.to_der
      assert_nil pkcs12.ca_certs

      decoded = OpenSSL::PKCS12.new(pkcs12.to_der)
      assert_cert @mycert, decoded.certificate
    end

    def test_create_with_chain
      chain = [@inter_cacert, @cacert]

      pkcs12 = OpenSSL::PKCS12.create(
        "omg",
        "hello",
        @mykey,
        @mycert,
        chain
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
        chain
      )

      decoded = OpenSSL::PKCS12.new(pkcs12.to_der, passwd)
      assert_equal chain.size, decoded.ca_certs.size
      assert_include_cert @cacert, decoded.ca_certs
      assert_include_cert @inter_cacert, decoded.ca_certs
      assert_cert @mycert, decoded.certificate
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
        nil,
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
        @mykey,
        @mycert,
        [],
        nil,
        nil,
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
          nil,
          nil,
          nil,
          "omg"
        )
      end
    end

    def test_new_with_one_key_and_one_cert
      # generated with:
      #   openssl version #=> OpenSSL 1.0.2h  3 May 2016
      #   openssl pkcs12 -in <@mycert> -inkey <RSA1024> -export -out <out>
      str = <<~EOF.unpack("m").first
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
vyl2WuMdEwQIMWFFphPkIUICAggA
      EOF
      p12 = OpenSSL::PKCS12.new(str, "abc123")

      assert_equal @mykey.to_der, p12.key.to_der
      assert_equal @mycert.subject.to_der, p12.certificate.subject.to_der
      assert_equal [], Array(p12.ca_certs)
    end

    def test_new_with_no_keys
      # generated with:
      #   openssl pkcs12 -in <@mycert> -nokeys -export -out <out>
      str = <<~EOF.unpack("m").first
MIIDHAIBAzCCAuIGCSqGSIb3DQEHAaCCAtMEggLPMIICyzCCAscGCSqGSIb3DQEH
BqCCArgwggK0AgEAMIICrQYJKoZIhvcNAQcBMBwGCiqGSIb3DQEMAQYwDgQIX4+W
irqwH40CAggAgIICgOaCyo+5+6IOVoGCCL80c50bkkzAwqdXxvkKExJSdcJz2uMU
0gRrKnZEjL5wrUsN8RwZu8DvgQTEhNEkKsUgM7AWainmN/EnwohIdHZAHpm6WD67
I9kLGp0/DHrqZrV9P2dLfhXLUSQE8PI0tqZPZ8UEABhizkViw4eISTkrOUN7pGbN
Qtx/oqgitXDuX2polbxYYDwt9vfHZhykHoKgew26SeJyZfeMs/WZ6olEI4cQUAFr
mvYGuC1AxEGTo9ERmU8Pm16j9Hr9PFk50WYe+rnk9oX3wJogQ7XUWS5kYf7XRycd
NDkNiwV/ts94bbuaGZp1YA6I48FXpIc8b5fX7t9tY0umGaWy0bARe1L7o0Y89EPe
lMg25rOM7j3uPtFG8whbSfdETSy57UxzzTcJ6UwexeaK6wb2jqEmj5AOoPLWeaX0
LyOAszR3v7OPAcjIDYZGdrbb3MZ2f2vo2pdQfu9698BrWhXuM7Odh73RLhJVreNI
aezNOAtPyBlvGiBQBGTzRIYHSLL5Y5aVj2vWLAa7hjm5qTL5C5mFdDIo6TkEMr6I
OsexNQofEGs19kr8nARXDlcbEimk2VsPj4efQC2CEXZNzURsKca82pa62MJ8WosB
DTFd8X06zZZ4nED50vLopZvyW4fyW60lELwOyThAdG8UchoAaz2baqP0K4de44yM
Y5/yPFDu4+GoimipJfbiYviRwbzkBxYW8+958ILh0RtagLbvIGxbpaym9PqGjOzx
ShNXjLK2aAFZsEizQ8kd09quJHU/ogq2cUXdqqhmOqPnUWrJVi/VCoRB3Pv1/lE4
mrUgr2YZ11rYvBw6g5XvNvFcSc53OKyV7SLn0dwwMTAhMAkGBSsOAwIaBQAEFEWP
1WRQykaoD4uJCpTx/wv0SLLBBAiDKI26LJK7xgICCAA=
      EOF
      p12 = OpenSSL::PKCS12.new(str, "abc123")

      assert_equal nil, p12.key
      assert_equal nil, p12.certificate
      assert_equal 1, p12.ca_certs.size
      assert_equal @mycert.subject.to_der, p12.ca_certs[0].subject.to_der
    end

    def test_new_with_no_certs
      # generated with:
      #   openssl pkcs12 -inkey <RSA1024> -nocerts -export -out <out>
      str = <<~EOF.unpack("m").first
MIIDJwIBAzCCAu0GCSqGSIb3DQEHAaCCAt4EggLaMIIC1jCCAtIGCSqGSIb3DQEH
AaCCAsMEggK/MIICuzCCArcGCyqGSIb3DQEMCgECoIICpjCCAqIwHAYKKoZIhvcN
AQwBAzAOBAg6AaYnJs84SwICCAAEggKAQzZH+fWSpcQYD1J7PsGSune85A++fLCQ
V7tacp2iv95GJkxwYmfTP176pJdgs00mceB9UJ/u9EX5nD0djdjjQjwo6sgKjY0q
cpVhZw8CMxw7kBD2dhtui0zT8z5hy03LePxsjEKsGiSbeVeeGbSfw/I6AAYbv+Uh
O/YPBGumeHj/D2WKnfsHJLQ9GAV3H6dv5VKYNxjciK7f/JEyZCuUQGIN64QFHDhJ
7fzLqd/ul3FZzJZO6a+dwvcgux09SKVXDRSeFmRCEX4b486iWhJJVspCo9P2KNne
ORrpybr3ZSwxyoICmjyo8gj0OSnEfdx9790Ej1takPqSA1wIdSdBLekbZqB0RBQg
DEuPOsXNo3QFi8ji1vu0WBRJZZSNC2hr5NL6lNR+DKxG8yzDll2j4W4BBIp22mAE
7QRX7kVxu17QJXQhOUac4Dd1qXmzebP8t6xkAxD9L7BWEN5OdiXWwSWGjVjMBneX
nYObi/3UT/aVc5WHMHK2BhCI1bwH51E6yZh06d5m0TQpYGUTWDJdWGBSrp3A+8jN
N2PMQkWBFrXP3smHoTEN4oZC4FWiPsIEyAkQsfKRhcV9lGKl2Xgq54ROTFLnwKoj
Z3zJScnq9qmNzvVZSMmDLkjLyDq0pxRxGKBvgouKkWY7VFFIwwBIJM39iDJ5NbBY
i1AQFTRsRSsZrNVPasCXrIq7bhMoJZb/YZOGBLNyJVqKUoYXhtwsajzSq54VlWft
JxsPayEd4Vi6O9EU1ahnj6qFEZiKFzsicgK2J1Rb8cYagrp0XWjHW0SBn5GVUWCg
GUokSFG/0JTdeYTo/sQuG4qNgJkOolRjpeI48Fciq5VUWLvVdKioXzAxMCEwCQYF
Kw4DAhoFAAQUYAuwVtGD1TdgbFK4Yal2XBgwUR4ECEawsN3rNaa6AgIIAA==
      EOF
      p12 = OpenSSL::PKCS12.new(str, "abc123")

      assert_equal @mykey.to_der, p12.key.to_der
      assert_equal nil, p12.certificate
      assert_equal [], Array(p12.ca_certs)
    end

    def test_dup
      p12 = OpenSSL::PKCS12.create("pass", "name", @mykey, @mycert)
      assert_equal p12.to_der, p12.dup.to_der
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
      assert_equal expected.to_der, actual.to_der
    end

    def assert_include_cert cert, ary
      der = cert.to_der
      ary.each do |candidate|
        if candidate.to_der == der
          return true
        end
      end
      false
    end
  end
end

end
