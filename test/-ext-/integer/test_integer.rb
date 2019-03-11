# frozen_string_literal: false
require 'test/unit'
require '-test-/integer'

class TestInteger < Test::Unit::TestCase
  FIXNUM_MIN = RbConfig::LIMITS['FIXNUM_MIN']
  FIXNUM_MAX = RbConfig::LIMITS['FIXNUM_MAX']

  def test_fixnum_range
    assert_bignum(FIXNUM_MIN-1)
    assert_fixnum(FIXNUM_MIN)
    assert_fixnum(FIXNUM_MAX)
    assert_bignum(FIXNUM_MAX+1)
  end

  def test_positive_pow
    assert_separately(%w[-r-test-/integer], "#{<<~"begin;"}\n#{<<~'end;'}", timeout: 3)
    begin;
      assert_equal(1, 1.positive_pow(1))
      assert_equal(0, 0.positive_pow(1))
      assert_equal(3, 3.positive_pow(1))
      assert_equal(-3, -3.positive_pow(1))
      assert_equal(9, -3.positive_pow(2))
    end;
  end
end
