# frozen_string_literal: false
require 'test/unit'

class TestMath < Test::Unit::TestCase
  def assert_infinity(a, *rest)
    rest = ["not infinity: #{a.inspect}"] if rest.empty?
    assert_predicate(a, :infinite?, *rest)
  end

  def assert_nan(a, *rest)
    rest = ["not nan: #{a.inspect}"] if rest.empty?
    assert_predicate(a, :nan?, *rest)
  end

  def assert_float(a, b)
    err = [Float::EPSILON * 4, [a.abs, b.abs].max * Float::EPSILON * 256].max
    assert_in_delta(a, b, err)
  end
  alias check assert_float

  def assert_float_and_int(exp_ary, act_ary)
    flo_exp, int_exp, flo_act, int_act = *exp_ary, *act_ary
    assert_float(flo_exp, flo_act)
    assert_equal(int_exp, int_act)
  end

  def test_atan2
    check(+0.0, Math.atan2(+0.0, +0.0))
    check(-0.0, Math.atan2(-0.0, +0.0))
    check(+Math::PI, Math.atan2(+0.0, -0.0))
    check(-Math::PI, Math.atan2(-0.0, -0.0))

    inf = Float::INFINITY
    expected = 3.0 * Math::PI / 4.0
    assert_nothing_raised { check(+expected, Math.atan2(+inf, -inf)) }
    assert_nothing_raised { check(-expected, Math.atan2(-inf, -inf)) }
    expected = Math::PI / 4.0
    assert_nothing_raised { check(+expected, Math.atan2(+inf, +inf)) }
    assert_nothing_raised { check(-expected, Math.atan2(-inf, +inf)) }

    check(0, Math.atan2(0, 1))
    check(Math::PI / 4, Math.atan2(1, 1))
    check(Math::PI / 2, Math.atan2(1, 0))
  end

  def test_cos
    check(1.0,  Math.cos(0 * Math::PI / 4))
    check(1.0 / Math.sqrt(2), Math.cos(1 * Math::PI / 4))
    check(0.0,  Math.cos(2 * Math::PI / 4))
    check(-1.0, Math.cos(4 * Math::PI / 4))
    check(0.0,  Math.cos(6 * Math::PI / 4))
    check(0.5403023058681398,  Math.cos(1))
  end

  def test_sin
    check(0.0,  Math.sin(0 * Math::PI / 4))
    check(1.0 / Math.sqrt(2), Math.sin(1 * Math::PI / 4))
    check(1.0,  Math.sin(2 * Math::PI / 4))
    check(0.0,  Math.sin(4 * Math::PI / 4))
    check(-1.0, Math.sin(6 * Math::PI / 4))
  end

  def test_tan
    check(0.0, Math.tan(0 * Math::PI / 4))
    check(1.0, Math.tan(1 * Math::PI / 4))
    assert_operator(Math.tan(2 * Math::PI / 4).abs, :>, 1024)
    check(0.0, Math.tan(4 * Math::PI / 4))
    assert_operator(Math.tan(6 * Math::PI / 4).abs, :>, 1024)
  end

  def test_acos
    check(0 * Math::PI / 4, Math.acos( 1.0))
    check(1 * Math::PI / 4, Math.acos( 1.0 / Math.sqrt(2)))
    check(2 * Math::PI / 4, Math.acos( 0.0))
    check(4 * Math::PI / 4, Math.acos(-1.0))
    assert_raise(Math::DomainError) { Math.acos(+1.0 + Float::EPSILON) }
    assert_raise(Math::DomainError) { Math.acos(-1.0 - Float::EPSILON) }
    assert_raise(Math::DomainError) { Math.acos(2.0) }
  end

  def test_asin
    check( 0 * Math::PI / 4, Math.asin( 0.0))
    check( 1 * Math::PI / 4, Math.asin( 1.0 / Math.sqrt(2)))
    check( 2 * Math::PI / 4, Math.asin( 1.0))
    check(-2 * Math::PI / 4, Math.asin(-1.0))
    assert_raise(Math::DomainError) { Math.asin(+1.0 + Float::EPSILON) }
    assert_raise(Math::DomainError) { Math.asin(-1.0 - Float::EPSILON) }
    assert_raise(Math::DomainError) { Math.asin(2.0) }
  end

  def test_atan
    check( 0 * Math::PI / 4, Math.atan( 0.0))
    check( 1 * Math::PI / 4, Math.atan( 1.0))
    check( 2 * Math::PI / 4, Math.atan(1.0 / 0.0))
    check(-1 * Math::PI / 4, Math.atan(-1.0))
  end

  def test_cosh
    check(1, Math.cosh(0))
    check((Math::E ** 1 + Math::E ** -1) / 2, Math.cosh(1))
    check((Math::E ** 2 + Math::E ** -2) / 2, Math.cosh(2))
  end

  def test_sinh
    check(0, Math.sinh(0))
    check((Math::E ** 1 - Math::E ** -1) / 2, Math.sinh(1))
    check((Math::E ** 2 - Math::E ** -2) / 2, Math.sinh(2))
  end

  def test_tanh
    check(Math.sinh(0) / Math.cosh(0), Math.tanh(0))
    check(Math.sinh(1) / Math.cosh(1), Math.tanh(1))
    check(Math.sinh(2) / Math.cosh(2), Math.tanh(2))
    check(+1.0, Math.tanh(+1000.0))
    check(-1.0, Math.tanh(-1000.0))
  end

  def test_acosh
    check(0, Math.acosh(1))
    check(1, Math.acosh((Math::E ** 1 + Math::E ** -1) / 2))
    check(2, Math.acosh((Math::E ** 2 + Math::E ** -2) / 2))
    assert_raise(Math::DomainError) { Math.acosh(1.0 - Float::EPSILON) }
    assert_raise(Math::DomainError) { Math.acosh(0) }
  end

  def test_asinh
    check(0, Math.asinh(0))
    check(1, Math.asinh((Math::E ** 1 - Math::E ** -1) / 2))
    check(2, Math.asinh((Math::E ** 2 - Math::E ** -2) / 2))
  end

  def test_atanh
    check(0, Math.atanh(Math.sinh(0) / Math.cosh(0)))
    check(1, Math.atanh(Math.sinh(1) / Math.cosh(1)))
    check(2, Math.atanh(Math.sinh(2) / Math.cosh(2)))
    assert_nothing_raised { assert_infinity(Math.atanh(1)) }
    assert_nothing_raised { assert_infinity(-Math.atanh(-1)) }
    assert_raise(Math::DomainError) { Math.atanh(+1.0 + Float::EPSILON) }
    assert_raise(Math::DomainError) { Math.atanh(-1.0 - Float::EPSILON) }
  end

  def test_exp
    check(1, Math.exp(0))
    check(Math.sqrt(Math::E), Math.exp(0.5))
    check(Math::E, Math.exp(1))
    check(Math::E ** 2, Math.exp(2))
  end

  def test_log
    check(0, Math.log(1))
    check(1, Math.log(Math::E))
    check(0, Math.log(1, 10))
    check(1, Math.log(10, 10))
    check(2, Math.log(100, 10))
    check(Math.log(2.0 ** 64), Math.log(1 << 64))
    check(Math.log(2) * 1024.0, Math.log(2 ** 1024))
    assert_nothing_raised { assert_infinity(Math.log(1.0/0)) }
    assert_nothing_raised { assert_infinity(-Math.log(+0.0)) }
    assert_nothing_raised { assert_infinity(-Math.log(-0.0)) }
    assert_raise(Math::DomainError) { Math.log(-1.0) }
    assert_raise(TypeError) { Math.log(1,nil) }
    assert_raise(Math::DomainError, '[ruby-core:62309] [ruby-Bug #9797]') { Math.log(1.0, -1.0) }
    assert_nothing_raised { assert_nan(Math.log(0.0, 0.0)) }
  end

  def test_log2
    check(0, Math.log2(1))
    check(1, Math.log2(2))
    check(2, Math.log2(4))
    check(Math.log2(2.0 ** 64), Math.log2(1 << 64))
    check(1024.0, Math.log2(2 ** 1024))
    assert_nothing_raised { assert_infinity(Math.log2(1.0/0)) }
    assert_nothing_raised { assert_infinity(-Math.log2(+0.0)) }
    assert_nothing_raised { assert_infinity(-Math.log2(-0.0)) }
    assert_raise(Math::DomainError) { Math.log2(-1.0) }
  end

  def test_log10
    check(0, Math.log10(1))
    check(1, Math.log10(10))
    check(2, Math.log10(100))
    check(Math.log10(2.0 ** 64), Math.log10(1 << 64))
    check(Math.log10(2) * 1024, Math.log10(2 ** 1024))
    assert_nothing_raised { assert_infinity(Math.log10(1.0/0)) }
    assert_nothing_raised { assert_infinity(-Math.log10(+0.0)) }
    assert_nothing_raised { assert_infinity(-Math.log10(-0.0)) }
    assert_raise(Math::DomainError) { Math.log10(-1.0) }
  end

  def test_sqrt
    check(0, Math.sqrt(0))
    check(1, Math.sqrt(1))
    check(2, Math.sqrt(4))
    assert_nothing_raised { assert_infinity(Math.sqrt(1.0/0)) }
    assert_equal("0.0", Math.sqrt(-0.0).to_s) # insure it is +0.0, not -0.0
    assert_raise(Math::DomainError) { Math.sqrt(-1.0) }
  end

  def test_cbrt
    check(1, Math.cbrt(1))
    check(-2, Math.cbrt(-8))
    check(3, Math.cbrt(27))
    check(-0.1, Math.cbrt(-0.001))
    assert_nothing_raised { assert_infinity(Math.cbrt(1.0/0)) }
    assert_operator(Math.cbrt(1.0 - Float::EPSILON), :<=, 1.0)
  end

  def test_frexp
    assert_float_and_int([0.0,  0], Math.frexp(0.0))
    assert_float_and_int([0.5,  0], Math.frexp(0.5))
    assert_float_and_int([0.5,  1], Math.frexp(1.0))
    assert_float_and_int([0.5,  2], Math.frexp(2.0))
    assert_float_and_int([0.75, 2], Math.frexp(3.0))
  end

  def test_ldexp
    check(0.0, Math.ldexp(0.0, 0.0))
    check(0.5, Math.ldexp(0.5, 0.0))
    check(1.0, Math.ldexp(0.5, 1.0))
    check(2.0, Math.ldexp(0.5, 2.0))
    check(3.0, Math.ldexp(0.75, 2.0))
  end

  def test_hypot
    check(5, Math.hypot(3, 4))
  end

  def test_erf
    check(0, Math.erf(0))
    check(1, Math.erf(1.0 / 0.0))
  end

  def test_erfc
    check(1, Math.erfc(0))
    check(0, Math.erfc(1.0 / 0.0))
  end

  def test_gamma
    sqrt_pi = Math.sqrt(Math::PI)
    check(4 * sqrt_pi / 3, Math.gamma(-1.5))
    check(-2 * sqrt_pi, Math.gamma(-0.5))
    check(sqrt_pi, Math.gamma(0.5))
    check(1, Math.gamma(1))
    check(sqrt_pi / 2, Math.gamma(1.5))
    check(1, Math.gamma(2))
    check(3 * sqrt_pi / 4, Math.gamma(2.5))
    check(2, Math.gamma(3))
    check(15 * sqrt_pi / 8, Math.gamma(3.5))
    check(6, Math.gamma(4))
    check(1.1240007277776077e+21, Math.gamma(23))
    check(2.5852016738885062e+22, Math.gamma(24))

    # no SEGV [ruby-core:25257]
    31.upto(65) do |i|
      i = 1 << i
      assert_infinity(Math.gamma(i), "Math.gamma(#{i}) should be INF")
      assert_infinity(Math.gamma(i-1), "Math.gamma(#{i-1}) should be INF")
    end

    assert_raise(Math::DomainError) { Math.gamma(-Float::INFINITY) }
    x = Math.gamma(-0.0)
    mesg = "Math.gamma(-0.0) should be -INF"
    assert_infinity(x, mesg)
    assert_predicate(x, :negative?, mesg)
  end

  def test_lgamma
    sqrt_pi = Math.sqrt(Math::PI)
    assert_float_and_int([Math.log(4 * sqrt_pi / 3),  1], Math.lgamma(-1.5))
    assert_float_and_int([Math.log(2 * sqrt_pi),     -1], Math.lgamma(-0.5))
    assert_float_and_int([Math.log(sqrt_pi),          1], Math.lgamma(0.5))
    assert_float_and_int([0,                          1], Math.lgamma(1))
    assert_float_and_int([Math.log(sqrt_pi / 2),      1], Math.lgamma(1.5))
    assert_float_and_int([0,                          1], Math.lgamma(2))
    assert_float_and_int([Math.log(3 * sqrt_pi / 4),  1], Math.lgamma(2.5))
    assert_float_and_int([Math.log(2),                1], Math.lgamma(3))
    assert_float_and_int([Math.log(15 * sqrt_pi / 8), 1], Math.lgamma(3.5))
    assert_float_and_int([Math.log(6),                1], Math.lgamma(4))

    assert_raise(Math::DomainError) { Math.lgamma(-Float::INFINITY) }
    x, sign = Math.lgamma(-0.0)
    mesg = "Math.lgamma(-0.0) should be [INF, -1]"
    assert_infinity(x, mesg)
    assert_predicate(x, :positive?, mesg)
    assert_equal(-1, sign, mesg)
  end

  def test_fixnum_to_f
    check(12.0, Math.sqrt(144))
  end

  def test_override_integer_to_f
    Integer.class_eval do
      alias _to_f to_f
      def to_f
        (self + 1)._to_f
      end
    end

    check(Math.cos((0 + 1)._to_f), Math.cos(0))
    check(Math.exp((0 + 1)._to_f), Math.exp(0))
    check(Math.log((0 + 1)._to_f), Math.log(0))
  ensure
    Integer.class_eval { undef to_f; alias to_f _to_f; undef _to_f }
  end

  def test_bignum_to_f
    check((1 << 65).to_f, Math.sqrt(1 << 130))
  end

  def test_override_bignum_to_f
    Integer.class_eval do
      alias _to_f to_f
      def to_f
        (self << 1)._to_f
      end
    end

    check(Math.cos((1 << 64 << 1)._to_f),  Math.cos(1 << 64))
    check(Math.log((1 << 64 << 1)._to_f),  Math.log(1 << 64))
  ensure
    Integer.class_eval { undef to_f; alias to_f _to_f; undef _to_f }
  end

  def test_rational_to_f
    check((2 ** 31).fdiv(3 ** 20), Math.sqrt((2 ** 62)/(3 ** 40).to_r))
  end

  def test_override_rational_to_f
    Rational.class_eval do
      alias _to_f to_f
      def to_f
        (self + 1)._to_f
      end
    end

    check(Math.cos((0r + 1)._to_f), Math.cos(0r))
    check(Math.exp((0r + 1)._to_f), Math.exp(0r))
    check(Math.log((0r + 1)._to_f), Math.log(0r))
  ensure
    Rational.class_eval { undef to_f; alias to_f _to_f; undef _to_f }
  end
end
