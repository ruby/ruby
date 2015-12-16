# frozen_string_literal: false
require_relative "testbase"

require 'bigdecimal/util'

class TestBigDecimalUtil < Test::Unit::TestCase
  def test_BigDecimal_to_d
    x = BigDecimal(1)
    assert_same(x, x.to_d)
  end

  def test_Integer_to_d
    assert_equal(BigDecimal(1), 1.to_d)
    assert_equal(BigDecimal(2<<100), (2<<100).to_d)
  end

  def test_Float_to_d_without_precision
    delta = 1.0/10**(Float::DIG)
    assert_in_delta(BigDecimal(0.5, Float::DIG), 0.5.to_d, delta)
    assert_in_delta(BigDecimal(355.0/113.0, Float::DIG), (355.0/113.0).to_d, delta)
    assert_equal(9.05.to_d.to_s('F'), "9.05")

    bug9214 = '[ruby-core:58858]'
    assert_equal((-0.0).to_d.sign, -1, bug9214)
  end

  def test_Float_to_d_with_precision
    digits = 5
    delta = 1.0/10**(digits)
    assert_in_delta(BigDecimal(0.5, 5), 0.5.to_d(digits), delta)
    assert_in_delta(BigDecimal(355.0/113.0, 5), (355.0/113.0).to_d(digits), delta)

    bug9214 = '[ruby-core:58858]'
    assert_equal((-0.0).to_d(digits).sign, -1, bug9214)
  end

  def test_Rational_to_d
    digits = 100
    delta = 1.0/10**(digits)
    assert_in_delta(BigDecimal(1.quo(2), digits), 1.quo(2).to_d(digits), delta)
    assert_in_delta(BigDecimal(355.quo(113), digits), 355.quo(113).to_d(digits), delta)
  end

  def test_Rational_to_d_with_zero_precision
    assert_raise(ArgumentError) { 355.quo(113).to_d(0) }
  end

  def test_Rational_to_d_with_negative_precision
    assert_raise(ArgumentError) { 355.quo(113).to_d(-42) }
  end
end
