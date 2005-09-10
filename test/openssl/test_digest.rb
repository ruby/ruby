begin
  require "openssl"
rescue LoadError
end
require "digest/md5"
require "test/unit"

if defined?(OpenSSL)

class OpenSSL::TestDigest < Test::Unit::TestCase
  def setup
    @d1 = OpenSSL::Digest::Digest::new("MD5")
    @d2 = OpenSSL::Digest::MD5.new
    @md = Digest::MD5.new
    @data = "DATA"
  end

  def teardown
    @d1 = @d2 = @md = nil
  end

  def test_digest
    assert_equal(@md.digest, @d1.digest)
    assert_equal(@md.hexdigest, @d1.hexdigest)
    @d1 << @data
    @d2 << @data
    @md << @data
    assert_equal(@md.digest, @d1.digest)
    assert_equal(@md.hexdigest, @d1.hexdigest)
    assert_equal(@d1.digest, @d2.digest)
    assert_equal(@d1.hexdigest, @d2.hexdigest)
    assert_equal(@md.digest, OpenSSL::Digest::MD5.digest(@data))
    assert_equal(@md.hexdigest, OpenSSL::Digest::MD5.hexdigest(@data))
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
    @d1.update(@data)
    assert_equal(@d1.name, @d1.dup.name, "dup")
    assert_equal(@d1.name, @d1.clone.name, "clone")
    assert_equal(@d1.digest, @d1.clone.digest, "clone .digest")
  end

  def test_reset
    @d1.update(@data)
    dig1 = @d1.digest
    @d1.reset
    @d1.update(@data)
    dig2 = @d1.digest
    assert_equal(dig1, dig2, "reset")
  end

  if OpenSSL::OPENSSL_VERSION_NUMBER > 0x00908000
    def test_098_features
      assert_equal("abd37534c7d9a2efb9465de931cd7055ffdb8879563ae98078d6d6d5", OpenSSL::Digest::SHA224.hexdigest("a"))
      assert_equal("ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb", OpenSSL::Digest::SHA256.hexdigest("a"))
      assert_equal("54a59b9f22b0b80880d8427e548b7c23abd873486e1f035dce9cd697e85175033caa88e6d57bc35efae0b5afd3145f31", OpenSSL::Digest::SHA384.hexdigest("a"))
      assert_equal("1f40fc92da241694750979ee6cf582f2d5d7d28e18335de05abc54d0560e0f5302860c652bf08d560252aa5e74210546f369fbbbce8c12cfc7957b2652fe9a75", OpenSSL::Digest::SHA512.hexdigest("a"))
    end
  end
end

end
