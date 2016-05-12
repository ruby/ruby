# frozen_string_literal: false
require_relative 'utils'

if defined?(OpenSSL::TestUtils)

class OpenSSL::TestBN < Test::Unit::TestCase
  def test_new_str
    e1 = OpenSSL::BN.new(999.to_s(16), 16) # OpenSSL::BN.new(str, 16) must be most stable
    e2 = OpenSSL::BN.new((2**107-1).to_s(16), 16)
    assert_equal(e1, OpenSSL::BN.new("999"))
    assert_equal(e2, OpenSSL::BN.new((2**107-1).to_s))
    assert_equal(e1, OpenSSL::BN.new("999", 10))
    assert_equal(e2, OpenSSL::BN.new((2**107-1).to_s, 10))
    assert_equal(e1, OpenSSL::BN.new("\x03\xE7", 2))
    assert_equal(e2, OpenSSL::BN.new("\a\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF", 2))
    assert_equal(e1, OpenSSL::BN.new("\x00\x00\x00\x02\x03\xE7", 0))
    assert_equal(e2, OpenSSL::BN.new("\x00\x00\x00\x0E\a\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF", 0))
  end

  def test_new_bn
    e1 = OpenSSL::BN.new(999.to_s(16), 16)
    e2 = OpenSSL::BN.new((2**107-1).to_s(16), 16)
    assert_equal(e1, OpenSSL::BN.new(e1))
    assert_equal(e2, OpenSSL::BN.new(e2))
  end

  def test_new_integer
    assert_equal(999.to_bn, OpenSSL::BN.new(999))
    assert_equal((2 ** 107 - 1).to_bn, OpenSSL::BN.new(2 ** 107 - 1))
    assert_equal(-999.to_bn, OpenSSL::BN.new(-999))
    assert_equal((-(2 ** 107 - 1)).to_bn, OpenSSL::BN.new(-(2 ** 107 - 1)))
  end

  def test_to_bn
    e1 = OpenSSL::BN.new(999.to_s(16), 16)
    e2 = OpenSSL::BN.new((2**107-1).to_s(16), 16)
    assert_equal(e1, 999.to_bn)
    assert_equal(e2, (2**107-1).to_bn)
  end

  def test_prime_p
    assert_equal(true, OpenSSL::BN.new((2 ** 107 - 1).to_s(16), 16).prime?)
    assert_equal(true, OpenSSL::BN.new((2 ** 127 - 1).to_s(16), 16).prime?(1))
  end

  def test_cmp_nil
    bn = OpenSSL::BN.new('1')
    assert_equal(false, bn == nil)
    assert_equal(true,  bn != nil)
  end
end

end
