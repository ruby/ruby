begin
  require "openssl"
rescue LoadError
end
require "test/unit"

if defined?(OpenSSL)

class OpenSSL::TestX509Name < Test::Unit::TestCase
  def setup
    @obj_type_tmpl = Hash.new(OpenSSL::ASN1::PRINTABLESTRING)
    @obj_type_tmpl.update(OpenSSL::X509::Name::OBJECT_TYPE_TEMPLATE)
  end

  def teardown
  end

  def test_s_new
    dn = [ ["C", "JP"], ["O", "example"], ["CN", "www.example.jp"] ]
    name = OpenSSL::X509::Name.new(dn)
    ary = name.to_a
    assert_equal("/C=JP/O=example/CN=www.example.jp", name.to_s)
    assert_equal("C", ary[0][0])
    assert_equal("O", ary[1][0])
    assert_equal("CN", ary[2][0])
    assert_equal("JP", ary[0][1])
    assert_equal("example", ary[1][1])
    assert_equal("www.example.jp", ary[2][1])
    assert_equal(OpenSSL::ASN1::PRINTABLESTRING, ary[0][2])
    assert_equal(OpenSSL::ASN1::UTF8STRING, ary[1][2])
    assert_equal(OpenSSL::ASN1::UTF8STRING, ary[2][2])

    dn = [
      ["countryName", "JP"],
      ["organizationName", "example"],
      ["commonName", "www.example.jp"]
    ]
    name = OpenSSL::X509::Name.new(dn)
    ary = name.to_a
    assert_equal("/C=JP/O=example/CN=www.example.jp", name.to_s)
    assert_equal("C", ary[0][0])
    assert_equal("O", ary[1][0])
    assert_equal("CN", ary[2][0])
    assert_equal("JP", ary[0][1])
    assert_equal("example", ary[1][1])
    assert_equal("www.example.jp", ary[2][1])
    assert_equal(OpenSSL::ASN1::PRINTABLESTRING, ary[0][2])
    assert_equal(OpenSSL::ASN1::UTF8STRING, ary[1][2])
    assert_equal(OpenSSL::ASN1::UTF8STRING, ary[2][2])

    name = OpenSSL::X509::Name.new(dn, @obj_type_tmpl)
    ary = name.to_a
    assert_equal("/C=JP/O=example/CN=www.example.jp", name.to_s)
    assert_equal(OpenSSL::ASN1::PRINTABLESTRING, ary[0][2])
    assert_equal(OpenSSL::ASN1::PRINTABLESTRING, ary[1][2])
    assert_equal(OpenSSL::ASN1::PRINTABLESTRING, ary[2][2])

    dn = [
      ["countryName", "JP", OpenSSL::ASN1::PRINTABLESTRING],
      ["organizationName", "example", OpenSSL::ASN1::PRINTABLESTRING],
      ["commonName", "www.example.jp", OpenSSL::ASN1::PRINTABLESTRING]
    ]
    name = OpenSSL::X509::Name.new(dn)
    ary = name.to_a
    assert_equal("/C=JP/O=example/CN=www.example.jp", name.to_s)
    assert_equal(OpenSSL::ASN1::PRINTABLESTRING, ary[0][2])
    assert_equal(OpenSSL::ASN1::PRINTABLESTRING, ary[1][2])
    assert_equal(OpenSSL::ASN1::PRINTABLESTRING, ary[2][2])

    dn = [
      ["DC", "org"],
      ["DC", "ruby-lang"],
      ["CN", "GOTOU Yuuzou"],
      ["emailAddress", "gotoyuzo@ruby-lang.org"],
      ["serialNumber", "123"],
    ]
    name = OpenSSL::X509::Name.new(dn)
    ary = name.to_a
    if OpenSSL::OPENSSL_VERSION_NUMBER < 0x00907000
      assert_equal("/DC=org/DC=ruby-lang/CN=GOTOU Yuuzou/Email=gotoyuzo@ruby-lang.org/SN=123", name.to_s)
    else
      assert_equal("/DC=org/DC=ruby-lang/CN=GOTOU Yuuzou/emailAddress=gotoyuzo@ruby-lang.org/serialNumber=123", name.to_s)
    end
    assert_equal("DC", ary[0][0])
    assert_equal("DC", ary[1][0])
    assert_equal("CN", ary[2][0])
    if OpenSSL::OPENSSL_VERSION_NUMBER < 0x00907000
      assert_equal("Email", ary[3][0])
      assert_equal("SN", ary[4][0])
    else
      assert_equal("emailAddress", ary[3][0])
      assert_equal("serialNumber", ary[4][0])
    end
    assert_equal("org", ary[0][1])
    assert_equal("ruby-lang", ary[1][1])
    assert_equal("GOTOU Yuuzou", ary[2][1])
    assert_equal("gotoyuzo@ruby-lang.org", ary[3][1])
    assert_equal("123", ary[4][1])
    assert_equal(OpenSSL::ASN1::IA5STRING, ary[0][2])
    assert_equal(OpenSSL::ASN1::IA5STRING, ary[1][2])
    assert_equal(OpenSSL::ASN1::UTF8STRING, ary[2][2])
    assert_equal(OpenSSL::ASN1::IA5STRING, ary[3][2])
    assert_equal(OpenSSL::ASN1::PRINTABLESTRING, ary[4][2])

    name_from_der = OpenSSL::X509::Name.new(name.to_der)
    assert_equal(name_from_der.to_s, name.to_s)
    assert_equal(name_from_der.to_a, name.to_a)
    assert_equal(name_from_der.to_der, name.to_der)
  end

  def test_s_parse
    dn = "/DC=org/DC=ruby-lang/CN=www.ruby-lang.org"
    name = OpenSSL::X509::Name.parse(dn)
    assert_equal(dn, name.to_s)
    ary = name.to_a
    assert_equal("DC", ary[0][0])
    assert_equal("DC", ary[1][0])
    assert_equal("CN", ary[2][0])
    assert_equal("org", ary[0][1])
    assert_equal("ruby-lang", ary[1][1])
    assert_equal("www.ruby-lang.org", ary[2][1])
    assert_equal(OpenSSL::ASN1::IA5STRING, ary[0][2])
    assert_equal(OpenSSL::ASN1::IA5STRING, ary[1][2])
    assert_equal(OpenSSL::ASN1::UTF8STRING, ary[2][2])

    dn2 = "DC=org, DC=ruby-lang, CN=www.ruby-lang.org"
    name = OpenSSL::X509::Name.parse(dn)
    ary = name.to_a
    assert_equal(dn, name.to_s)
    assert_equal("org", ary[0][1])
    assert_equal("ruby-lang", ary[1][1])
    assert_equal("www.ruby-lang.org", ary[2][1])

    name = OpenSSL::X509::Name.parse(dn, @obj_type_tmpl)
    ary = name.to_a
    assert_equal(OpenSSL::ASN1::IA5STRING, ary[0][2])
    assert_equal(OpenSSL::ASN1::IA5STRING, ary[1][2])
    assert_equal(OpenSSL::ASN1::PRINTABLESTRING, ary[2][2])
  end

  def test_add_entry
    dn = [
      ["DC", "org"],
      ["DC", "ruby-lang"],
      ["CN", "GOTOU Yuuzou"],
      ["emailAddress", "gotoyuzo@ruby-lang.org"],
      ["serialNumber", "123"],
    ]
    name = OpenSSL::X509::Name.new
    dn.each{|attr| name.add_entry(*attr) }
    ary = name.to_a
    if OpenSSL::OPENSSL_VERSION_NUMBER < 0x00907000
      assert_equal("/DC=org/DC=ruby-lang/CN=GOTOU Yuuzou/Email=gotoyuzo@ruby-lang.org/SN=123", name.to_s)
    else
      assert_equal("/DC=org/DC=ruby-lang/CN=GOTOU Yuuzou/emailAddress=gotoyuzo@ruby-lang.org/serialNumber=123", name.to_s)
    end
    assert_equal("DC", ary[0][0])
    assert_equal("DC", ary[1][0])
    assert_equal("CN", ary[2][0])
    if OpenSSL::OPENSSL_VERSION_NUMBER < 0x00907000
      assert_equal("Email", ary[3][0])
      assert_equal("SN", ary[4][0])
    else
      assert_equal("emailAddress", ary[3][0])
      assert_equal("serialNumber", ary[4][0])
    end
    assert_equal("org", ary[0][1])
    assert_equal("ruby-lang", ary[1][1])
    assert_equal("GOTOU Yuuzou", ary[2][1])
    assert_equal("gotoyuzo@ruby-lang.org", ary[3][1])
    assert_equal("123", ary[4][1])
    assert_equal(OpenSSL::ASN1::IA5STRING, ary[0][2])
    assert_equal(OpenSSL::ASN1::IA5STRING, ary[1][2])
    assert_equal(OpenSSL::ASN1::UTF8STRING, ary[2][2])
    assert_equal(OpenSSL::ASN1::IA5STRING, ary[3][2])
    assert_equal(OpenSSL::ASN1::PRINTABLESTRING, ary[4][2])
  end
end

end
