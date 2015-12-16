# frozen_string_literal: false
begin
  require "openssl"
rescue LoadError
end

class OpenSSL::TestRandom < Test::Unit::TestCase
  def test_random_bytes
    assert_equal("", OpenSSL::Random.random_bytes(0))
    assert_equal(12, OpenSSL::Random.random_bytes(12).bytesize)
  end

  def test_pseudo_bytes
    assert_equal("", OpenSSL::Random.pseudo_bytes(0))
    assert_equal(12, OpenSSL::Random.pseudo_bytes(12).bytesize)
  end
end if defined?(OpenSSL::Random)
