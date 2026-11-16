# frozen_string_literal: false
require 'test/unit'
require '-test-/integer'

class Test_Integer < Test::Unit::TestCase
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
      assert_equal(1, Bug::Integer.positive_pow(1, 1))
      assert_equal(0, Bug::Integer.positive_pow(0, 1))
      assert_equal(3, Bug::Integer.positive_pow(3, 1))
      assert_equal(-3, Bug::Integer.positive_pow(-3, 1))
      assert_equal(9, Bug::Integer.positive_pow(-3, 2))
      rb_len_max = RbConfig::LIMITS['RB_LEN_MAX']
      assert_equal(rb_len_max, Bug::Integer.positive_pow(rb_len_max, 1))
      rb_len_min = RbConfig::LIMITS['RB_LEN_MIN']
      assert_equal(rb_len_min, Bug::Integer.positive_pow(rb_len_min, 1))
    end;
  end
end
