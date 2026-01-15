# frozen_string_literal: true
require_relative "utils"

if defined?(OpenSSL)

class OpenSSL::TestX509Request < OpenSSL::TestCase
  def setup
    super
    @rsa1 = Fixtures.pkey("rsa-1")
    @rsa2 = Fixtures.pkey("rsa-2")
    @dn = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=GOTOU Yuuzou")
  end

  def issue_csr(ver, dn, key, digest)
    req = OpenSSL::X509::Request.new
    req.version = ver
    req.subject = dn
    req.public_key = key
    req.sign(key, digest)
    req
  end

  def test_public_key
    req = issue_csr(0, @dn, @rsa1, "SHA256")
    assert_kind_of(OpenSSL::PKey::RSA, req.public_key)
    assert_equal(@rsa1.public_to_der, req.public_key.public_to_der)
    req = OpenSSL::X509::Request.new(req.to_der)
    assert_equal(@rsa1.public_to_der, req.public_key.public_to_der)
  end

  def test_version
    req = issue_csr(0, @dn, @rsa1, "SHA256")
    assert_equal(0, req.version)
    req = OpenSSL::X509::Request.new(req.to_der)
    assert_equal(0, req.version)
  end

  def test_subject
    req = issue_csr(0, @dn, @rsa1, "SHA256")
    assert_equal(@dn.to_der, req.subject.to_der)
    req = OpenSSL::X509::Request.new(req.to_der)
    assert_equal(@dn.to_der, req.subject.to_der)
  end

  def test_signature_algorithm
    req = issue_csr(0, @dn, @rsa1, "SHA256")
    assert_equal("sha256WithRSAEncryption", req.signature_algorithm) # ln
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

    req0 = issue_csr(0, @dn, @rsa1, "SHA256")
    attrs.each{|attr| req0.add_attribute(attr) }
    req1 = issue_csr(0, @dn, @rsa1, "SHA256")
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

  def test_sign_digest_instance
    req1 = issue_csr(0, @dn, @rsa1, "SHA256")
    req2 = issue_csr(0, @dn, @rsa1, OpenSSL::Digest.new("SHA256"))
    assert_equal(req1.to_der, req2.to_der)
  end

  def test_sign_and_verify
    req = issue_csr(0, @dn, @rsa1, "SHA256")
    assert_equal(true, req.verify(@rsa1))
    assert_equal(false, req.verify(@rsa2))
    ec = OpenSSL::PKey::EC.generate("prime256v1")
    assert_equal(false, request_error_returns_false { req.verify(ec) })
    req.subject = OpenSSL::X509::Name.parse_rfc2253("CN=FooBarFooBar,C=JP")
    assert_equal(false, req.verify(@rsa1))
  end

  def test_sign_and_verify_nil_digest
    # Ed25519 is not FIPS-approved.
    omit_on_fips
    ed25519 = OpenSSL::PKey::generate_key("ED25519")
    req = issue_csr(0, @dn, ed25519, nil)
    assert_equal(false, request_error_returns_false { req.verify(@rsa1) })
    assert_equal(false, request_error_returns_false { req.verify(@rsa2) })
    assert_equal(false, req.verify(OpenSSL::PKey::generate_key("ED25519")))
    assert_equal(true, req.verify(ed25519))
    req.public_key = @rsa1
    assert_equal(false, req.verify(ed25519))
  end

  def test_dup
    req = issue_csr(0, @dn, @rsa1, "SHA256")
    assert_equal(req.to_der, req.dup.to_der)
  end

  def test_eq
    req1 = issue_csr(0, @dn, @rsa1, "SHA256")
    req2 = issue_csr(0, @dn, @rsa1, "SHA256")
    req3 = issue_csr(0, @dn, @rsa1, "SHA512")

    assert_equal false, req1 == 12345
    assert_equal true, req1 == req2
    assert_equal false, req1 == req3
  end

  def test_marshal
    req = issue_csr(0, @dn, @rsa1, "SHA256")
    deserialized = Marshal.load(Marshal.dump(req))

    assert_equal req.to_der, deserialized.to_der
  end

  private

  def request_error_returns_false
    yield
  rescue OpenSSL::X509::RequestError
    false
  end
end

end
