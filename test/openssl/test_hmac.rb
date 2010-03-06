begin
  require "openssl"
rescue LoadError
end
require "test/unit"

class OpenSSL::TestHMAC < Test::Unit::TestCase
  def setup
    @digest = OpenSSL::Digest::MD5
    @key = "KEY"
    @data = "DATA"
    @h1 = OpenSSL::HMAC.new(@key, @digest.new)
    @h2 = OpenSSL::HMAC.new(@key, "MD5")
  end

  def teardown
  end

  def test_hmac
    @h1.update(@data)
    @h2.update(@data)
    assert_equal(@h1.digest, @h2.digest)

    assert_equal(OpenSSL::HMAC.digest(@digest.new, @key, @data), @h1.digest, "digest")
    assert_equal(OpenSSL::HMAC.hexdigest(@digest.new, @key, @data), @h1.hexdigest, "hexdigest")

    assert_equal(OpenSSL::HMAC.digest("MD5", @key, @data), @h2.digest, "digest")
    assert_equal(OpenSSL::HMAC.hexdigest("MD5", @key, @data), @h2.hexdigest, "hexdigest")
  end

  def test_dup
    @h1.update(@data)
    h = @h1.dup
    assert_equal(@h1.digest, h.digest, "dup digest")
  end

  def test_sha256
    digest256 = OpenSSL::Digest::Digest.new("sha256")
    assert_equal(
      "\210\236-\3270\331Yq\265\177sE\266\231hXa\332\250\026\235O&c*\307\001\227~\260n\362",
      OpenSSL::HMAC.digest(digest256, 'blah', "blah"))
    assert_equal(
      "889e2dd730d95971b57f7345b699685861daa8169d4f26632ac701977eb06ef2",
      OpenSSL::HMAC.hexdigest(digest256, 'blah', "blah"))
  end
end
