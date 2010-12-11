require_relative 'utils'

class  OpenSSL::TestASN1 < Test::Unit::TestCase
  def test_decode
    subj = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=TestCA")
    key = OpenSSL::TestUtils::TEST_KEY_RSA1024
    now = Time.at(Time.now.to_i) # suppress usec
    s = 0xdeadbeafdeadbeafdeadbeafdeadbeaf
    exts = [
      ["basicConstraints","CA:TRUE,pathlen:1",true],
      ["keyUsage","keyCertSign, cRLSign",true],
      ["subjectKeyIdentifier","hash",false],
    ]
    dgst = OpenSSL::Digest::SHA1.new
    cert = OpenSSL::TestUtils.issue_cert(
      subj, key, s, now, now+3600, exts, nil, nil, dgst)


    asn1 = OpenSSL::ASN1.decode(cert)
    assert_equal(OpenSSL::ASN1::Sequence, asn1.class)
    assert_equal(3, asn1.value.size)
    tbs_cert, sig_alg, sig_val = *asn1.value

    assert_equal(OpenSSL::ASN1::Sequence, tbs_cert.class)
    assert_equal(8, tbs_cert.value.size)

    version = tbs_cert.value[0]
    assert_equal(:CONTEXT_SPECIFIC, version.tag_class)
    assert_equal(0, version.tag)
    assert_equal(1, version.value.size)
    assert_equal(OpenSSL::ASN1::Integer, version.value[0].class)
    assert_equal(2, version.value[0].value)

    serial = tbs_cert.value[1]
    assert_equal(OpenSSL::ASN1::Integer, serial.class)
    assert_equal(0xdeadbeafdeadbeafdeadbeafdeadbeaf, serial.value)

    sig = tbs_cert.value[2]
    assert_equal(OpenSSL::ASN1::Sequence, sig.class)
    assert_equal(2, sig.value.size)
    assert_equal(OpenSSL::ASN1::ObjectId, sig.value[0].class)
    assert_equal("1.2.840.113549.1.1.5", sig.value[0].oid)
    assert_equal(OpenSSL::ASN1::Null, sig.value[1].class)

    dn = tbs_cert.value[3] # issuer
    assert_equal(subj.hash, OpenSSL::X509::Name.new(dn).hash)
    assert_equal(OpenSSL::ASN1::Sequence, dn.class)
    assert_equal(3, dn.value.size)
    assert_equal(OpenSSL::ASN1::Set, dn.value[0].class)
    assert_equal(OpenSSL::ASN1::Set, dn.value[1].class)
    assert_equal(OpenSSL::ASN1::Set, dn.value[2].class)
    assert_equal(1, dn.value[0].value.size)
    assert_equal(1, dn.value[1].value.size)
    assert_equal(1, dn.value[2].value.size)
    assert_equal(OpenSSL::ASN1::Sequence, dn.value[0].value[0].class)
    assert_equal(OpenSSL::ASN1::Sequence, dn.value[1].value[0].class)
    assert_equal(OpenSSL::ASN1::Sequence, dn.value[2].value[0].class)
    assert_equal(2, dn.value[0].value[0].value.size)
    assert_equal(2, dn.value[1].value[0].value.size)
    assert_equal(2, dn.value[2].value[0].value.size)
    oid, value = *dn.value[0].value[0].value
    assert_equal(OpenSSL::ASN1::ObjectId, oid.class)
    assert_equal("0.9.2342.19200300.100.1.25", oid.oid)
    assert_equal(OpenSSL::ASN1::IA5String, value.class)
    assert_equal("org", value.value)
    oid, value = *dn.value[1].value[0].value
    assert_equal(OpenSSL::ASN1::ObjectId, oid.class)
    assert_equal("0.9.2342.19200300.100.1.25", oid.oid)
    assert_equal(OpenSSL::ASN1::IA5String, value.class)
    assert_equal("ruby-lang", value.value)
    oid, value = *dn.value[2].value[0].value
    assert_equal(OpenSSL::ASN1::ObjectId, oid.class)
    assert_equal("2.5.4.3", oid.oid)
    assert_equal(OpenSSL::ASN1::UTF8String, value.class)
    assert_equal("TestCA", value.value)

    validity = tbs_cert.value[4]
    assert_equal(OpenSSL::ASN1::Sequence, validity.class)
    assert_equal(2, validity.value.size)
    assert_equal(OpenSSL::ASN1::UTCTime, validity.value[0].class)
    assert_equal(now, validity.value[0].value)
    assert_equal(OpenSSL::ASN1::UTCTime, validity.value[1].class)
    assert_equal(now+3600, validity.value[1].value)

    dn = tbs_cert.value[5] # subject
    assert_equal(subj.hash, OpenSSL::X509::Name.new(dn).hash)
    assert_equal(OpenSSL::ASN1::Sequence, dn.class)
    assert_equal(3, dn.value.size)
    assert_equal(OpenSSL::ASN1::Set, dn.value[0].class)
    assert_equal(OpenSSL::ASN1::Set, dn.value[1].class)
    assert_equal(OpenSSL::ASN1::Set, dn.value[2].class)
    assert_equal(1, dn.value[0].value.size)
    assert_equal(1, dn.value[1].value.size)
    assert_equal(1, dn.value[2].value.size)
    assert_equal(OpenSSL::ASN1::Sequence, dn.value[0].value[0].class)
    assert_equal(OpenSSL::ASN1::Sequence, dn.value[1].value[0].class)
    assert_equal(OpenSSL::ASN1::Sequence, dn.value[2].value[0].class)
    assert_equal(2, dn.value[0].value[0].value.size)
    assert_equal(2, dn.value[1].value[0].value.size)
    assert_equal(2, dn.value[2].value[0].value.size)
    oid, value = *dn.value[0].value[0].value
    assert_equal(OpenSSL::ASN1::ObjectId, oid.class)
    assert_equal("0.9.2342.19200300.100.1.25", oid.oid)
    assert_equal(OpenSSL::ASN1::IA5String, value.class)
    assert_equal("org", value.value)
    oid, value = *dn.value[1].value[0].value
    assert_equal(OpenSSL::ASN1::ObjectId, oid.class)
    assert_equal("0.9.2342.19200300.100.1.25", oid.oid)
    assert_equal(OpenSSL::ASN1::IA5String, value.class)
    assert_equal("ruby-lang", value.value)
    oid, value = *dn.value[2].value[0].value
    assert_equal(OpenSSL::ASN1::ObjectId, oid.class)
    assert_equal("2.5.4.3", oid.oid)
    assert_equal(OpenSSL::ASN1::UTF8String, value.class)
    assert_equal("TestCA", value.value)

    pkey = tbs_cert.value[6]
    assert_equal(OpenSSL::ASN1::Sequence, pkey.class)
    assert_equal(2, pkey.value.size)
    assert_equal(OpenSSL::ASN1::Sequence, pkey.value[0].class)
    assert_equal(2, pkey.value[0].value.size)
    assert_equal(OpenSSL::ASN1::ObjectId, pkey.value[0].value[0].class)
    assert_equal("1.2.840.113549.1.1.1", pkey.value[0].value[0].oid)
    assert_equal(OpenSSL::ASN1::BitString, pkey.value[1].class)
    assert_equal(0, pkey.value[1].unused_bits)
    spkey = OpenSSL::ASN1.decode(pkey.value[1].value)
    assert_equal(OpenSSL::ASN1::Sequence, spkey.class)
    assert_equal(2, spkey.value.size)
    assert_equal(OpenSSL::ASN1::Integer, spkey.value[0].class)
    assert_equal(143085709396403084580358323862163416700436550432664688288860593156058579474547937626086626045206357324274536445865308750491138538454154232826011964045825759324933943290377903384882276841880081931690695505836279972214003660451338124170055999155993192881685495391496854691199517389593073052473319331505702779271, spkey.value[0].value)
    assert_equal(OpenSSL::ASN1::Integer, spkey.value[1].class)
    assert_equal(65537, spkey.value[1].value)

    extensions = tbs_cert.value[7]
    assert_equal(:CONTEXT_SPECIFIC, extensions.tag_class)
    assert_equal(3, extensions.tag)
    assert_equal(1, extensions.value.size)
    assert_equal(OpenSSL::ASN1::Sequence, extensions.value[0].class)
    assert_equal(3, extensions.value[0].value.size)

    ext = extensions.value[0].value[0]  # basicConstraints
    assert_equal(OpenSSL::ASN1::Sequence, ext.class)
    assert_equal(3, ext.value.size)
    assert_equal(OpenSSL::ASN1::ObjectId, ext.value[0].class)
    assert_equal("2.5.29.19",  ext.value[0].oid)
    assert_equal(OpenSSL::ASN1::Boolean, ext.value[1].class)
    assert_equal(true, ext.value[1].value)
    assert_equal(OpenSSL::ASN1::OctetString, ext.value[2].class)
    extv = OpenSSL::ASN1.decode(ext.value[2].value)
    assert_equal(OpenSSL::ASN1::Sequence, extv.class)
    assert_equal(2, extv.value.size)
    assert_equal(OpenSSL::ASN1::Boolean, extv.value[0].class)
    assert_equal(true, extv.value[0].value)
    assert_equal(OpenSSL::ASN1::Integer, extv.value[1].class)
    assert_equal(1, extv.value[1].value)

    ext = extensions.value[0].value[1]  # keyUsage
    assert_equal(OpenSSL::ASN1::Sequence, ext.class)
    assert_equal(3, ext.value.size)
    assert_equal(OpenSSL::ASN1::ObjectId, ext.value[0].class)
    assert_equal("2.5.29.15",  ext.value[0].oid)
    assert_equal(OpenSSL::ASN1::Boolean, ext.value[1].class)
    assert_equal(true, ext.value[1].value)
    assert_equal(OpenSSL::ASN1::OctetString, ext.value[2].class)
    extv = OpenSSL::ASN1.decode(ext.value[2].value)
    assert_equal(OpenSSL::ASN1::BitString, extv.class)
    str = "\000"; str[0] = 0b00000110.chr
    assert_equal(str, extv.value)

    ext = extensions.value[0].value[2]  # subjetKeyIdentifier
    assert_equal(OpenSSL::ASN1::Sequence, ext.class)
    assert_equal(2, ext.value.size)
    assert_equal(OpenSSL::ASN1::ObjectId, ext.value[0].class)
    assert_equal("2.5.29.14",  ext.value[0].oid)
    assert_equal(OpenSSL::ASN1::OctetString, ext.value[1].class)
    extv = OpenSSL::ASN1.decode(ext.value[1].value)
    assert_equal(OpenSSL::ASN1::OctetString, extv.class)
    sha1 = OpenSSL::Digest::SHA1.new
    sha1.update(pkey.value[1].value)
    assert_equal(sha1.digest, extv.value)

    assert_equal(OpenSSL::ASN1::Sequence, sig_alg.class)
    assert_equal(2, sig_alg.value.size)
    assert_equal(OpenSSL::ASN1::ObjectId, pkey.value[0].value[0].class)
    assert_equal("1.2.840.113549.1.1.1", pkey.value[0].value[0].oid)
    assert_equal(OpenSSL::ASN1::Null, pkey.value[0].value[1].class)

    assert_equal(OpenSSL::ASN1::BitString, sig_val.class)
    cululated_sig = key.sign(OpenSSL::Digest::SHA1.new, tbs_cert.to_der)
    assert_equal(cululated_sig, sig_val.value)
  end

  def test_encode_boolean
    encode_decode_test(OpenSSL::ASN1::Boolean, [true, false])
  end

  def test_encode_integer
    encode_decode_test(OpenSSL::ASN1::Integer, [72, -127, -128, 128, -1, 0, 1, -(2**12345), 2**12345])
  end

  def encode_decode_test(type, values)
    values.each do |v|
      assert_equal(v, OpenSSL::ASN1.decode(type.new(v).to_der).value)
    end
  end
end if defined?(OpenSSL)
