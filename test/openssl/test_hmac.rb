begin
  require "openssl"
rescue LoadError
end
require "test/unit"

if defined?(OpenSSL)

class OpenSSL::TestHMAC < Test::Unit::TestCase
  def setup
    @digest = OpenSSL::Digest::MD5.new
    @key = "KEY"
    @data = "DATA"
    @h1 = OpenSSL::HMAC.new(@key, @digest)
    @h2 = OpenSSL::HMAC.new(@key, @digest)
  end

  def teardown
  end

  def test_hmac
    @h1.update(@data)
    assert_equal(OpenSSL::HMAC.digest(@digest, @key, @data), @h1.digest, "digest")
    assert_equal(OpenSSL::HMAC.hexdigest(@digest, @key, @data), @h1.hexdigest, "hexdigest")
  end

  def test_dup
    @h1.update(@data)
    h = @h1.dup
    assert_equal(@h1.digest, h.digest, "dup digest")
  end
end

end
