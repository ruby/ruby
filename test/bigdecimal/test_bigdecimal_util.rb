# frozen_string_literal: false
require_relative "helper"
require 'bigdecimal/util'

class TestBigDecimalUtil < Test::Unit::TestCase
  include TestBigDecimalBase

  def test_BigDecimal_to_d
    x = BigDecimal(1)
    assert_same(x, x.to_d)
  end

  def test_Integer_to_d
    assert_equal(BigDecimal(1), 1.to_d)
    assert_equal(BigDecimal(2<<100), (2<<100).to_d)

    assert(1.to_d.frozen?)
  end

  def test_Float_to_d_without_precision
    delta = 1.0/10**(Float::DIG+1)
    assert_in_delta(BigDecimal(0.5, 0), 0.5.to_d, delta)
    assert_in_delta(BigDecimal(355.0/113.0, 0), (355.0/113.0).to_d, delta)

    assert_equal(9.05, 9.05.to_d.to_f)
    assert_equal("9.05", 9.05.to_d.to_s('F'))

    assert_equal("65.6", 65.6.to_d.to_s("F"))

    assert_equal(Math::PI, Math::PI.to_d.to_f)

    bug9214 = '[ruby-core:58858]'
    assert_equal((-0.0).to_d.sign, -1, bug9214)

    assert_raise(TypeError) { 0.3.to_d(nil) }
    assert_raise(TypeError) { 0.3.to_d(false) }

    assert(1.1.to_d.frozen?)

    assert_equal(BigDecimal("999_999.9999"), 999_999.9999.to_d)
  end

  def test_Float_to_d_with_precision
    digits = 5
    delta = 1.0/10**(digits)
    assert_in_delta(BigDecimal(0.5, 5), 0.5.to_d(digits), delta)
    assert_in_delta(BigDecimal(355.0/113.0, 5), (355.0/113.0).to_d(digits), delta)

    bug9214 = '[ruby-core:58858]'
    assert_equal((-0.0).to_d(digits).sign, -1, bug9214)

    assert(1.1.to_d(digits).frozen?)
  end

  def test_Float_to_d_bug13331
    assert_equal(64.4.to_d,
                 1.to_d * 64.4,
                 "[ruby-core:80234] [Bug #13331]")

    assert_equal((2*Math::PI).to_d,
                 2.to_d * Math::PI,
                 "[ruby-core:80234] [Bug #13331]")
  end

  def test_Float_to_d_issue_192
    # https://github.com/ruby/bigdecimal/issues/192
    # https://github.com/rails/rails/pull/42125
    if BASE_FIG == 9
      flo = 1_000_000_000.12345
      big = BigDecimal("0.100000000012345e10")
    else  # BASE_FIG == 4
      flo = 1_0000.12
      big = BigDecimal("0.1000012e5")
    end
    assert_equal(flo.to_d, big, "[ruby/bigdecimal#192]")
  end

  def test_Rational_to_d
    digits = 100
    delta = 1.0/10**(digits)
    assert_in_delta(BigDecimal(1.quo(2), digits), 1.quo(2).to_d(digits), delta)
    assert_in_delta(BigDecimal(355.quo(113), digits), 355.quo(113).to_d(digits), delta)

    assert(355.quo(113).to_d(digits).frozen?)
  end

  def test_Rational_to_d_with_zero_precision
    assert_equal(BigDecimal(355.quo(113), 0), 355.quo(113).to_d(0))
  end

  def test_Rational_to_d_with_negative_precision
    assert_raise(ArgumentError) { 355.quo(113).to_d(-42) }
  end

  def test_Complex_to_d
    BigDecimal.save_rounding_mode do
      BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_EVEN)

      assert_equal(BigDecimal("1"), Complex(1, 0).to_d)
      assert_equal(BigDecimal("0.333333333333333333333"),
                   Complex(1.quo(3), 0).to_d(21))
      assert_equal(BigDecimal("0.1234567"), Complex(0.1234567, 0).to_d)
      assert_equal(BigDecimal("0.1235"), Complex(0.1234567, 0).to_d(4))

      assert_raise_with_message(ArgumentError, "can't omit precision for a Rational.") { Complex(1.quo(3), 0).to_d }

      assert_raise_with_message(ArgumentError, "Unable to make a BigDecimal from non-zero imaginary number") { Complex(1, 1).to_d }
    end
  end

  def test_String_to_d
    assert_equal(BigDecimal('1'), "1__1_1".to_d)
    assert_equal(BigDecimal('2.5'), "2.5".to_d)
    assert_equal(BigDecimal('2.5'), "2.5 degrees".to_d)
    assert_equal(BigDecimal('2.5e1'), "2.5e1 degrees".to_d)
    assert_equal(BigDecimal('0'), "degrees 100.0".to_d)
    assert_equal(BigDecimal('0.125'), "0.1_2_5".to_d)
    assert_equal(BigDecimal('0.125'), "0.1_2_5__".to_d)
    assert_equal(BigDecimal('1'), "1_.125".to_d)
    assert_equal(BigDecimal('1'), "1._125".to_d)
    assert_equal(BigDecimal('0.1'), "0.1__2_5".to_d)
    assert_equal(BigDecimal('0.1'), "0.1_e10".to_d)
    assert_equal(BigDecimal('0.1'), "0.1e_10".to_d)
    assert_equal(BigDecimal('1'), "0.1e1__0".to_d)
    assert_equal(BigDecimal('1.2'), "1.2.3".to_d)
    assert_equal(BigDecimal('1'), "1.".to_d)
    assert_equal(BigDecimal('1'), "1e".to_d)

    assert("2.5".to_d.frozen?)
  end

  def test_invalid_String_to_d
    assert_equal("invalid".to_d, BigDecimal('0.0'))
  end

  def test_Nil_to_d
    assert_equal(nil.to_d, BigDecimal('0.0'))

    assert(nil.to_d)
  end
end
