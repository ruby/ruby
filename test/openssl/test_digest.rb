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
end

end
