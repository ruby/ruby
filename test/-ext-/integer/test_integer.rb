# frozen_string_literal: false
require 'test/unit'
require '-test-/integer'

class TestInteger < Test::Unit::TestCase
  FIXNUM_MIN = Integer::FIXNUM_MIN
  FIXNUM_MAX = Integer::FIXNUM_MAX

  def test_fixnum_range
    assert_bignum(FIXNUM_MIN-1)
    assert_fixnum(FIXNUM_MIN)
    assert_fixnum(FIXNUM_MAX)
    assert_bignum(FIXNUM_MAX+1)
  end
end
