# frozen_string_literal: false
require_relative "utils"

class OpenSSL::TestRandom < OpenSSL::TestCase
  def test_random_bytes
    assert_equal("", OpenSSL::Random.random_bytes(0))
    assert_equal(12, OpenSSL::Random.random_bytes(12).bytesize)
  end

  def test_pseudo_bytes
    assert_equal("", OpenSSL::Random.pseudo_bytes(0))
    assert_equal(12, OpenSSL::Random.pseudo_bytes(12).bytesize)
  end
end if defined?(OpenSSL::Random)
