# frozen_string_literal: false
require_relative "utils"

if defined?(OpenSSL::TestUtils)

class OpenSSL::TestX509Request < OpenSSL::TestCase
  def setup
    super
    @rsa1024 = Fixtures.pkey("rsa1024")
    @rsa2048 = Fixtures.pkey("rsa2048")
    @dsa256  = Fixtures.pkey("dsa256")
    @dsa512  = Fixtures.pkey("dsa512")
    @dn = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=GOTOU Yuuzou")
  end

  def issue_csr(ver, dn, key, digest)
    req = OpenSSL::X509::Request.new
    req.version = ver
    req.subject = dn
    req.public_key = key.public_key
    req.sign(key, digest)
    req
  end

  def test_public_key
    req = issue_csr(0, @dn, @rsa1024, OpenSSL::Digest::SHA1.new)
    assert_equal(@rsa1024.public_key.to_der, req.public_key.to_der)
    req = OpenSSL::X509::Request.new(req.to_der)
    assert_equal(@rsa1024.public_key.to_der, req.public_key.to_der)

    req = issue_csr(0, @dn, @dsa512, OpenSSL::TestUtils::DSA_SIGNATURE_DIGEST.new)
    assert_equal(@dsa512.public_key.to_der, req.public_key.to_der)
    req = OpenSSL::X509::Request.new(req.to_der)
    assert_equal(@dsa512.public_key.to_der, req.public_key.to_der)
  end

  def test_version
    req = issue_csr(0, @dn, @rsa1024, OpenSSL::Digest::SHA1.new)
    assert_equal(0, req.version)
    req = OpenSSL::X509::Request.new(req.to_der)
    assert_equal(0, req.version)

    req = issue_csr(1, @dn, @rsa1024, OpenSSL::Digest::SHA1.new)
    assert_equal(1, req.version)
    req = OpenSSL::X509::Request.new(req.to_der)
    assert_equal(1, req.version)
  end

  def test_subject
    req = issue_csr(0, @dn, @rsa1024, OpenSSL::Digest::SHA1.new)
    assert_equal(@dn.to_der, req.subject.to_der)
    req = OpenSSL::X509::Request.new(req.to_der)
    assert_equal(@dn.to_der, req.subject.to_der)
  end

  def create_ext_req(exts)
    ef = OpenSSL::X509::ExtensionFactory.new
    exts = exts.collect{|e| ef.create_extension(*e) }
    return OpenSSL::ASN1::Set([OpenSSL::ASN1::Sequence(exts)])
  end

  def get_ext_req(ext_req_value)
    set = OpenSSL::ASN1.decode(ext_req_value)
    seq = set.value[0]
    seq.value.collect{|asn1ext|
      OpenSSL::X509::Extension.new(asn1ext).to_a
    }
  end

  def test_attr
    exts = [
      ["keyUsage", "Digital Signature, Key Encipherment", true],
      ["subjectAltName", "email:gotoyuzo@ruby-lang.org", false],
    ]
    attrval = create_ext_req(exts)
    attrs = [
      OpenSSL::X509::Attribute.new("extReq", attrval),
      OpenSSL::X509::Attribute.new("msExtReq", attrval),
    ]

    req0 = issue_csr(0, @dn, @rsa1024, OpenSSL::Digest::SHA1.new)
    attrs.each{|attr| req0.add_attribute(attr) }
    req1 = issue_csr(0, @dn, @rsa1024, OpenSSL::Digest::SHA1.new)
    req1.attributes = attrs
    assert_equal(req0.to_der, req1.to_der)

    attrs = req0.attributes
    assert_equal(2, attrs.size)
    assert_equal("extReq", attrs[0].oid)
    assert_equal("msExtReq", attrs[1].oid)
    assert_equal(exts, get_ext_req(attrs[0].value))
    assert_equal(exts, get_ext_req(attrs[1].value))

    req = OpenSSL::X509::Request.new(req0.to_der)
    attrs = req.attributes
    assert_equal(2, attrs.size)
    assert_equal("extReq", attrs[0].oid)
    assert_equal("msExtReq", attrs[1].oid)
    assert_equal(exts, get_ext_req(attrs[0].value))
    assert_equal(exts, get_ext_req(attrs[1].value))
  end

  def test_sign_and_verify_rsa_sha1
    req = issue_csr(0, @dn, @rsa1024, OpenSSL::Digest::SHA1.new)
    assert_equal(true,  req.verify(@rsa1024))
    assert_equal(false, req.verify(@rsa2048))
    assert_equal(false, request_error_returns_false { req.verify(@dsa256) })
    assert_equal(false, request_error_returns_false { req.verify(@dsa512) })
    req.version = 1
    assert_equal(false, req.verify(@rsa1024))
  end

  def test_sign_and_verify_rsa_md5
    req = issue_csr(0, @dn, @rsa2048, OpenSSL::Digest::MD5.new)
    assert_equal(false, req.verify(@rsa1024))
    assert_equal(true,  req.verify(@rsa2048))
    assert_equal(false, request_error_returns_false { req.verify(@dsa256) })
    assert_equal(false, request_error_returns_false { req.verify(@dsa512) })
    req.subject = OpenSSL::X509::Name.parse("/C=JP/CN=FooBar")
    assert_equal(false, req.verify(@rsa2048))
  rescue OpenSSL::X509::RequestError # RHEL7 disables MD5
  end

  def test_sign_and_verify_dsa
    req = issue_csr(0, @dn, @dsa512, OpenSSL::TestUtils::DSA_SIGNATURE_DIGEST.new)
    assert_equal(false, request_error_returns_false { req.verify(@rsa1024) })
    assert_equal(false, request_error_returns_false { req.verify(@rsa2048) })
    assert_equal(false, req.verify(@dsa256))
    assert_equal(true,  req.verify(@dsa512))
    req.public_key = @rsa1024.public_key
    assert_equal(false, req.verify(@dsa512))
  end

  def test_sign_and_verify_rsa_dss1
    req = issue_csr(0, @dn, @rsa1024, OpenSSL::Digest::DSS1.new)
    assert_equal(true,  req.verify(@rsa1024))
    assert_equal(false, req.verify(@rsa2048))
    assert_equal(false, request_error_returns_false { req.verify(@dsa256) })
    assert_equal(false, request_error_returns_false { req.verify(@dsa512) })
    req.version = 1
    assert_equal(false, req.verify(@rsa1024))
  rescue OpenSSL::X509::RequestError
    pend
  end if defined?(OpenSSL::Digest::DSS1)

  def test_sign_and_verify_dsa_md5
    assert_raise(OpenSSL::X509::RequestError){
      issue_csr(0, @dn, @dsa512, OpenSSL::Digest::MD5.new) }
  end

  def test_dup
    req = issue_csr(0, @dn, @rsa1024, OpenSSL::Digest::SHA1.new)
    assert_equal(req.to_der, req.dup.to_der)
  end

  private

  def request_error_returns_false
    yield
  rescue OpenSSL::X509::RequestError
    false
  end
end

end
