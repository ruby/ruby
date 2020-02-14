# frozen_string_literal: true
require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestDigest < OpenSSL::TestCase
  def setup
    super
    @d1 = OpenSSL::Digest.new("MD5")
    @d2 = OpenSSL::Digest::MD5.new
  end

  def test_digest
    null_hex = "d41d8cd98f00b204e9800998ecf8427e"
    null_bin = [null_hex].pack("H*")
    data = "DATA"
    hex = "e44f9e348e41cb272efa87387728571b"
    bin = [hex].pack("H*")
    assert_equal(null_bin, @d1.digest)
    assert_equal(null_hex, @d1.hexdigest)
    @d1 << data
    assert_equal(bin, @d1.digest)
    assert_equal(hex, @d1.hexdigest)
    assert_equal(bin, OpenSSL::Digest::MD5.digest(data))
    assert_equal(hex, OpenSSL::Digest::MD5.hexdigest(data))
  end

  def test_eql
    assert(@d1 == @d2, "==")
    d = @d1.clone
    assert(d == @d1, "clone")
  end

  def test_info
    assert_equal("MD5", @d1.name, "name")
    assert_equal("MD5", @d2.name, "name")
    assert_equal(16, @d1.size, "size")
  end

  def test_dup
    @d1.update("DATA")
    assert_equal(@d1.name, @d1.dup.name, "dup")
    assert_equal(@d1.name, @d1.clone.name, "clone")
    assert_equal(@d1.digest, @d1.clone.digest, "clone .digest")
  end

  def test_reset
    @d1.update("DATA")
    dig1 = @d1.digest
    @d1.reset
    @d1.update("DATA")
    dig2 = @d1.digest
    assert_equal(dig1, dig2, "reset")
  end

  def test_required_digests
    algorithms = OpenSSL::Digest::ALGORITHMS
    required = %w{MD4 MD5 RIPEMD160 SHA1 SHA224 SHA256 SHA384 SHA512}

    required.each do |name|
      assert_include(algorithms, name)
    end
  end

  def test_digest_constants
    algorithms = OpenSSL::Digest::ALGORITHMS

    algorithms.each do |name|
      assert_not_nil(OpenSSL::Digest.new(name))
      klass = OpenSSL::Digest.const_get(name.tr('-', '_'))
      assert_not_nil(klass.new)
    end
  end

  def test_digest_by_oid_and_name
    check_digest(OpenSSL::ASN1::ObjectId.new("MD5"))
    check_digest(OpenSSL::ASN1::ObjectId.new("SHA1"))
  end

  def encode16(str)
    str.unpack("H*").first
  end

  def test_sha2
    sha224_a = "abd37534c7d9a2efb9465de931cd7055ffdb8879563ae98078d6d6d5"
    sha256_a = "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb"
    sha384_a = "54a59b9f22b0b80880d8427e548b7c23abd873486e1f035dce9cd697e85175033caa88e6d57bc35efae0b5afd3145f31"
    sha512_a = "1f40fc92da241694750979ee6cf582f2d5d7d28e18335de05abc54d0560e0f5302860c652bf08d560252aa5e74210546f369fbbbce8c12cfc7957b2652fe9a75"

    assert_equal(sha224_a, OpenSSL::Digest::SHA224.hexdigest("a"))
    assert_equal(sha256_a, OpenSSL::Digest::SHA256.hexdigest("a"))
    assert_equal(sha384_a, OpenSSL::Digest::SHA384.hexdigest("a"))
    assert_equal(sha512_a, OpenSSL::Digest::SHA512.hexdigest("a"))

    assert_equal(sha224_a, encode16(OpenSSL::Digest::SHA224.digest("a")))
    assert_equal(sha256_a, encode16(OpenSSL::Digest::SHA256.digest("a")))
    assert_equal(sha384_a, encode16(OpenSSL::Digest::SHA384.digest("a")))
    assert_equal(sha512_a, encode16(OpenSSL::Digest::SHA512.digest("a")))
  end

  def test_sha3
    pend "SHA3 is not implemented" unless OpenSSL::Digest.const_defined?(:SHA3_224)
    s224 = '6b4e03423667dbb73b6e15454f0eb1abd4597f9a1b078e3f5b5a6bc7'
    s256 = 'a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a'
    s384 = '0c63a75b845e4f7d01107d852e4c2485c51a50aaaa94fc61995e71bbee983a2ac3713831264adb47fb6bd1e058d5f004'
    s512 = 'a69f73cca23a9ac5c8b567dc185a756e97c982164fe25859e0d1dcc1475c80a615b2123af1f5f94c11e3e9402c3ac558f500199d95b6d3e301758586281dcd26'
    assert_equal(OpenSSL::Digest::SHA3_224.hexdigest(""), s224)
    assert_equal(OpenSSL::Digest::SHA3_256.hexdigest(""), s256)
    assert_equal(OpenSSL::Digest::SHA3_384.hexdigest(""), s384)
    assert_equal(OpenSSL::Digest::SHA3_512.hexdigest(""), s512)
  end

  def test_digest_by_oid_and_name_sha2
    check_digest(OpenSSL::ASN1::ObjectId.new("SHA224"))
    check_digest(OpenSSL::ASN1::ObjectId.new("SHA256"))
    check_digest(OpenSSL::ASN1::ObjectId.new("SHA384"))
    check_digest(OpenSSL::ASN1::ObjectId.new("SHA512"))
  end

  def test_openssl_digest
    assert_equal OpenSSL::Digest::MD5, OpenSSL::Digest("MD5")

    assert_raise NameError do
      OpenSSL::Digest("no such digest")
    end
  end

  private

  def check_digest(oid)
    d = OpenSSL::Digest.new(oid.sn)
    assert_not_nil(d)
    d = OpenSSL::Digest.new(oid.ln)
    assert_not_nil(d)
    d = OpenSSL::Digest.new(oid.oid)
    assert_not_nil(d)
  end
end

end
