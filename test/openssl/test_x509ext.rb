begin
  require "openssl"
  require File.join(File.dirname(__FILE__), "utils.rb")
rescue LoadError
end
require "test/unit"

if defined?(OpenSSL)

class OpenSSL::TestX509Extension < Test::Unit::TestCase
  def setup
    @basic_constraints_value = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Boolean(true),   # CA
      OpenSSL::ASN1::Integer(2)       # pathlen
    ])
    @basic_constraints = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::ObjectId("basicConstraints"),
      OpenSSL::ASN1::Boolean(true),
      OpenSSL::ASN1::OctetString(@basic_constraints_value.to_der),
    ])
  end

  def teardown
  end

  def test_new
    ext = OpenSSL::X509::Extension.new(@basic_constraints.to_der)
    assert_equal("basicConstraints", ext.oid)
    assert_equal(true, ext.critical?)
    assert_equal("CA:TRUE, pathlen:2", ext.value)

    ext = OpenSSL::X509::Extension.new("2.5.29.19",
                                       @basic_constraints_value.to_der, true)
    assert_equal(@basic_constraints.to_der, ext.to_der)
  end

  def test_create_by_factory
    ef = OpenSSL::X509::ExtensionFactory.new

    bc = ef.create_extension("basicConstraints", "critical, CA:TRUE, pathlen:2")
    assert_equal(@basic_constraints.to_der, bc.to_der)

    bc = ef.create_extension("basicConstraints", "CA:TRUE, pathlen:2", true)
    assert_equal(@basic_constraints.to_der, bc.to_der)

    begin
      ef.config = OpenSSL::Config.parse(<<-_end_of_cnf_)
      [crlDistPts]
      URI.1 = http://www.example.com/crl
      URI.2 = ldap://ldap.example.com/cn=ca?certificateRevocationList;binary
      _end_of_cnf_
    rescue NotImplementedError
      return
    end

    cdp = ef.create_extension("crlDistributionPoints", "@crlDistPts")
    assert_equal(false, cdp.critical?)
    assert_equal("crlDistributionPoints", cdp.oid)
    assert_match(%{URI:http://www\.example\.com/crl}, cdp.value)
    assert_match(
      %r{URI:ldap://ldap\.example\.com/cn=ca\?certificateRevocationList;binary},
      cdp.value)

    cdp = ef.create_extension("crlDistributionPoints", "critical, @crlDistPts")
    assert_equal(true, cdp.critical?)
    assert_equal("crlDistributionPoints", cdp.oid)
    assert_match(%{URI:http://www.example.com/crl}, cdp.value)
    assert_match(
      %r{URI:ldap://ldap.example.com/cn=ca\?certificateRevocationList;binary},
      cdp.value)
  end

  # JRUBY-3888
  # Problems with subjectKeyIdentifier with non 20-bytes sha1 digested keys
  def test_certificate_with_rare_extension
    cert_file = File.expand_path('max.pem', File.dirname(__FILE__))
    cer = OpenSSL::X509::Certificate.new(File.read(cert_file))
    exts = Hash.new
    cer.extensions.each{|ext| exts[ext.oid] = ext.value}

    assert exts["subjectKeyIdentifier"] == "4C:B9:E1:DC:7A:AC:35:CF"
  end

  def test_extension_from_20_byte_sha1_digests
    cert_file = File.expand_path('common.pem', File.dirname(__FILE__))
    cer = OpenSSL::X509::Certificate.new(File.read(cert_file))
    exts = Hash.new
    cer.extensions.each{|ext| exts[ext.oid] = ext.value}

    assert exts["subjectKeyIdentifier"] == "B4:AC:83:5D:21:FB:D6:8A:56:7E:B2:49:6D:69:BB:E4:6F:D8:5A:AC"
  end

end

end
