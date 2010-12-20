begin
  require "openssl"
  require File.join(File.dirname(__FILE__), "utils.rb")
rescue LoadError
end

if defined?(OpenSSL)

class OpenSSL::TestBN < Test::Unit::TestCase
  def test_integer_to_bn
    assert_equal(999.to_bn, OpenSSL::BN.new(999.to_s(16), 16))
    assert_equal((2 ** 107 - 1).to_bn, OpenSSL::BN.new((2 ** 107 - 1).to_s(16), 16))
  end

  def test_prime_p
    OpenSSL::BN.new((2 ** 107 - 1).to_s(16), 16).prime?
    OpenSSL::BN.new((2 ** 127 - 1).to_s(16), 16).prime?(1)
  end
end

end
