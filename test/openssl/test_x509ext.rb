# frozen_string_literal: true
require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestX509Extension < OpenSSL::TestCase
  def setup
    super
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

    ef.config = OpenSSL::Config.parse(<<-_end_of_cnf_)
    [crlDistPts]
    URI.1 = http://www.example.com/crl
    URI.2 = ldap://ldap.example.com/cn=ca?certificateRevocationList;binary

    [certPolicies]
    policyIdentifier = 2.23.140.1.2.1
    CPS.1 = http://cps.example.com
    _end_of_cnf_

    cdp = ef.create_extension("crlDistributionPoints", "@crlDistPts")
    assert_equal(false, cdp.critical?)
    assert_equal("crlDistributionPoints", cdp.oid)
    assert_include(cdp.value, "URI:http://www.example.com/crl")
    assert_include(cdp.value,
      "URI:ldap://ldap.example.com/cn=ca?certificateRevocationList;binary")

    cdp = ef.create_extension("crlDistributionPoints", "critical, @crlDistPts")
    assert_equal(true, cdp.critical?)
    assert_equal("crlDistributionPoints", cdp.oid)
    assert_include(cdp.value, "URI:http://www.example.com/crl")
    assert_include(cdp.value,
      "URI:ldap://ldap.example.com/cn=ca?certificateRevocationList;binary")

    cp = ef.create_extension("certificatePolicies", "@certPolicies")
    assert_equal(false, cp.critical?)
    assert_equal("certificatePolicies", cp.oid)
    assert_include(cp.value, "2.23.140.1.2.1")
    assert_include(cp.value, "http://cps.example.com")
  end

  def test_factory_create_extension_sn_ln
    ef = OpenSSL::X509::ExtensionFactory.new
    bc_sn = ef.create_extension("basicConstraints", "critical, CA:TRUE, pathlen:2")
    bc_ln = ef.create_extension("X509v3 Basic Constraints", "critical, CA:TRUE, pathlen:2")
    assert_equal(@basic_constraints.to_der, bc_sn.to_der)
    assert_equal(@basic_constraints.to_der, bc_ln.to_der)
  end

  def test_factory_create_extension_oid
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.config = OpenSSL::Config.parse(<<~_end_of_cnf_)
      [basic_constraints]
      cA = BOOLEAN:TRUE
      pathLenConstraint = INTEGER:2
    _end_of_cnf_
    bc_oid = ef.create_extension("2.5.29.19", "ASN1:SEQUENCE:basic_constraints", true)
    assert_equal(@basic_constraints.to_der, bc_oid.to_der)
  end

  def test_dup
    ext = OpenSSL::X509::Extension.new(@basic_constraints.to_der)
    assert_equal(@basic_constraints.to_der, ext.to_der)
    assert_equal(ext.to_der, ext.dup.to_der)
  end

  def test_eq
    ext1 = OpenSSL::X509::Extension.new(@basic_constraints.to_der)
    ef = OpenSSL::X509::ExtensionFactory.new
    ext2 = ef.create_extension("basicConstraints", "critical, CA:TRUE, pathlen:2")
    ext3 = ef.create_extension("basicConstraints", "critical, CA:TRUE")

    assert_equal false, ext1 == 12345
    assert_equal true, ext1 == ext2
    assert_equal false, ext1 == ext3
  end

  def test_marshal
    ef = OpenSSL::X509::ExtensionFactory.new
    ext = ef.create_extension("basicConstraints", "critical, CA:TRUE, pathlen:2")
    deserialized = Marshal.load(Marshal.dump(ext))

    assert_equal ext.to_der, deserialized.to_der
  end

  def test_value_der
    ext = OpenSSL::X509::Extension.new(@basic_constraints.to_der)
    assert_equal @basic_constraints_value.to_der, ext.value_der
  end
end

end
