# coding: UTF-8

require_relative 'utils'

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

  def test_binary_update
    data = "Lücíllé: Bût... yøü sáîd hé wås âlrîght.\nDr. Físhmån: Yés. Hé's løst hîs léft hånd, sø hé's gøîng tø bé åll rîght"
    hmac = OpenSSL::HMAC.new("qShkcwN92rsM9nHfdnP4ugcVU2iI7iM/trovs01ZWok", "SHA256")
    result = hmac.update(data).hexdigest
    assert_equal "a13984b929a07912e4e21c5720876a8e150d6f67f854437206e7f86547248396", result
  end
end if defined?(OpenSSL::TestUtils)
