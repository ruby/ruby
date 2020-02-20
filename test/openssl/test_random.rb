# frozen_string_literal: true
require_relative "utils"

if defined?(OpenSSL)

class OpenSSL::TestRandom < OpenSSL::TestCase
  def test_random_bytes
    assert_equal("", OpenSSL::Random.random_bytes(0))
    assert_equal(12, OpenSSL::Random.random_bytes(12).bytesize)
  end

  def test_pseudo_bytes
    # deprecated as of OpenSSL 1.1.0
    assert_equal("", OpenSSL::Random.pseudo_bytes(0))
    assert_equal(12, OpenSSL::Random.pseudo_bytes(12).bytesize)
  end if OpenSSL::Random.methods.include?(:pseudo_bytes)
end

end
