require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestBN < Test::Unit::TestCase
  def test_integer_to_bn
    assert_equal(999.to_bn, OpenSSL::BN.new(999.to_s(16), 16))
    assert_equal((2 ** 107 - 1).to_bn, OpenSSL::BN.new((2 ** 107 - 1).to_s(16), 16))
  end
end

end
