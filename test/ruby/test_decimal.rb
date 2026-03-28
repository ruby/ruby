# frozen_string_literal: false
require 'test/unit'

class TestDecimal < Test::Unit::TestCase
  class RationalBackedNumeric < Numeric
    def initialize(value)
      @value = value
    end

    def to_r = @value
  end

  class BrokenToRNumeric < Numeric
    def to_r
      raise RangeError, "bad to_r"
    end
  end

  def test_from_integer
    d = Decimal(42)
    assert_instance_of(Decimal, d)
    assert_equal("42.0", d.to_s)
  end

  def test_from_string
    d = Decimal("42.42")
    assert_instance_of(Decimal, d)
    assert_equal("42.42", d.to_s)
  end

  def test_from_string_no_fraction
    assert_equal("7.0", Decimal("7").to_s)
  end

  def test_from_string_leading_zeros
    assert_equal("1.000001", Decimal("1.000001").to_s)
  end

  def test_from_float
    d = Decimal(42.42)
    assert_instance_of(Decimal, d)
    assert_equal("42.42", d.to_s)
  end

  def test_from_float_exact
    assert_equal(Decimal("0.25"), Decimal(0.25))
  end

  def test_from_rational
    d = Decimal(Rational(1, 2))
    assert_instance_of(Decimal, d)
    assert_equal(Rational(1, 2), d.to_r)
  end

  def test_from_numeric_via_to_r
    d = Decimal(RationalBackedNumeric.new(Rational(1999, 100)))
    assert_instance_of(Decimal, d)
    assert_equal("19.99", d.to_s)
  end

  def test_from_real_complex
    assert_equal(Decimal(1), Decimal(Complex(1, 0)))
  end

  def test_from_decimal_idempotent
    d = Decimal(42)
    assert_same(d, Decimal(d))
  end

  def test_from_negative_string
    assert_equal("-99.5", Decimal("-99.5").to_s)
  end

  def test_from_positive_sign_string
    assert_equal("3.14", Decimal("+3.14").to_s)
  end

  def test_exception_false_bad_string
    assert_nil(Decimal("bad", exception: false))
  end

  def test_exception_false_overflow
    assert_nil(Decimal(10**40, exception: false))
  end

  def test_exception_false_does_not_swallow_numeric_to_r_errors
    assert_raise(RangeError) { Decimal(BrokenToRNumeric.new, exception: false) }
  end

  def test_exception_false_non_real_complex
    assert_nil(Decimal(Complex(1, 2), exception: false))
  end

  def test_rejects_invalid_string
    assert_raise(ArgumentError) { Decimal("abc") }
  end

  def test_rejects_unsupported_type
    assert_raise(TypeError) { Decimal(:foo) }
  end

  def test_new_is_undefined
    assert_raise(NoMethodError) { Decimal.new(0) }
  end
  def test_addition
    assert_equal(Decimal(3), Decimal(1) + Decimal(2))
  end

  def test_subtraction
    assert_equal(Decimal(2), Decimal(5) - Decimal(3))
  end

  def test_multiplication
    assert_equal(Decimal(42), Decimal(6) * Decimal(7))
  end

  def test_multiplication_decimals
    assert_equal(Decimal("0.02"), Decimal("0.1") * Decimal("0.2"))
  end

  def test_division
    assert_equal(Decimal("2.5"), Decimal(10) / Decimal(4))
  end

  def test_division_by_zero
    assert_raise(ZeroDivisionError) { Decimal(1) / Decimal(0) }
  end

  def test_negation
    assert_equal(Decimal(-5), -Decimal(5))
  end

  def test_quo
    assert_equal(Decimal("2.5"), Decimal(10).quo(Decimal(4)))
  end

  def test_fdiv
    assert_in_delta(2.5, Decimal(10).fdiv(Decimal(4)))
  end
  def test_power
    assert_equal(Decimal(8), Decimal(2) ** 3)
  end

  def test_power_zero
    assert_equal(Decimal(1), Decimal(42) ** 0)
  end

  def test_power_negative
    assert_equal(Decimal("0.5"), Decimal(2) ** -1)
  end

  def test_power_negative_base
    assert_equal(Decimal(4), Decimal(-2) ** 2)
    assert_equal(Decimal(-8), Decimal(-2) ** 3)
  end

  def test_power_zero_base_negative_exp
    assert_raise(ZeroDivisionError) { Decimal(0) ** -1 }
  end

  def test_power_zero_base_zero_exp
    assert_equal(Decimal(1), Decimal(0) ** 0)
  end

  def test_power_non_integer_exponent
    assert_raise(TypeError) { Decimal(2) ** 1.5 }
  end
  def test_modulo
    assert_equal(Decimal(2), Decimal(5) % Decimal(3))
  end

  def test_modulo_negative_dividend
    assert_equal(Decimal(1), Decimal(-5) % Decimal(3))
  end

  def test_modulo_negative_divisor
    assert_equal(Decimal("-1.0"), Decimal(5) % Decimal(-3))
  end

  def test_modulo_both_negative
    assert_equal(Decimal("-2.0"), Decimal(-5) % Decimal(-3))
  end

  def test_modulo_method
    assert_equal(Decimal(2), Decimal(5).modulo(Decimal(3)))
  end

  def test_modulo_by_zero
    assert_raise(ZeroDivisionError) { Decimal(1) % Decimal(0) }
  end

  def test_divmod
    assert_equal([1, Decimal(2)], Decimal(5).divmod(Decimal(3)))
  end

  def test_divmod_negative_dividend
    assert_equal([-2, Decimal(1)], Decimal(-5).divmod(Decimal(3)))
  end

  def test_divmod_negative_divisor
    assert_equal([-2, Decimal("-1.0")], Decimal(5).divmod(Decimal(-3)))
  end

  def test_divmod_both_negative
    assert_equal([1, Decimal("-2.0")], Decimal(-5).divmod(Decimal(-3)))
  end

  def test_divmod_by_zero
    assert_raise(ZeroDivisionError) { Decimal(1).divmod(Decimal(0)) }
  end

  def test_remainder
    assert_equal(Decimal(2), Decimal(5).remainder(Decimal(3)))
  end

  def test_remainder_negative
    assert_equal(Decimal(-2), Decimal(-5).remainder(Decimal(3)))
  end

  def test_div
    assert_equal(1, Decimal(5).div(Decimal(3)))
  end

  def test_div_negative_divisor
    assert_equal(-2, Decimal(5).div(Decimal(-3)))
  end

  def test_div_both_negative
    assert_equal(1, Decimal(-5).div(Decimal(-3)))
  end

  def test_div_by_zero
    assert_raise(ZeroDivisionError) { Decimal(1).div(Decimal(0)) }
  end

  def test_mul_truncates_toward_zero
    a = Decimal("0.000000000000000007")
    assert_equal(Decimal(0), (-a) * Decimal("0.000000000000000003"))
  end

  def test_div_truncates_toward_zero
    assert_equal(Decimal("-3.333333333333333333"), Decimal(-10) / Decimal(3))
    assert_equal(Decimal("3.333333333333333333"), Decimal(10) / Decimal(3))
  end
  def test_compare
    assert_equal(-1, Decimal(1) <=> Decimal(2))
    assert_equal(0, Decimal(1) <=> Decimal(1))
    assert_equal(1, Decimal(2) <=> Decimal(1))
  end

  def test_compare_operators
    assert_operator(Decimal(1), :<, Decimal(2))
    assert_operator(Decimal(1), :<=, Decimal(1))
    assert_operator(Decimal(1), :>=, Decimal(1))
    assert_operator(Decimal(2), :>, Decimal(1))
    assert_not_operator(Decimal(1), :>, Decimal(2))
  end

  def test_compare_with_integer
    assert_equal(0, Decimal(5) <=> 5)
  end

  def test_compare_with_rational
    assert_equal(0, Decimal("0.5") <=> Rational(1, 2))
  end

  def test_compare_with_non_numeric
    assert_nil(Decimal(1) <=> "foo")
  end

  def test_sorting
    assert_equal([Decimal(1), Decimal(2), Decimal(3)],
                 [Decimal(3), Decimal(1), Decimal(2)].sort)
  end

  def test_eql
    assert_operator(Decimal(5), :eql?, Decimal(5))
  end

  def test_eql_non_decimal
    assert_not_operator(Decimal(5), :eql?, 5)
  end

  def test_hash_equality
    assert_equal(Decimal(5).hash, Decimal(5).hash)
  end

  def test_hash_key_lookup
    assert_equal(:one, {Decimal(1) => :one}[Decimal(1)])
  end

  def test_hash_as_key
    h = {}
    h[Decimal(0)] = 0
    h[Decimal(1)] = 1
    h[Decimal(2)] = 2
    assert_equal(3, h.size)
    assert_equal(2, h[Decimal(2)])

    h[Decimal(0)] = 9
    assert_equal(3, h.size)
    assert_equal(9, h[Decimal(0)])
  end

  def test_equality
    assert_equal(Decimal(1), Decimal(1))
    assert_not_equal(Decimal(1), Decimal(2))
    assert_not_equal(Decimal(1), nil)
    assert_not_equal(Decimal(1), '')
  end

  def test_equality_with_integer
    assert_equal(Decimal(5), 5)
  end

  def test_equality_with_rational
    assert_equal(Decimal("0.5"), Rational(1, 2))
  end

  def test_equality_float
    assert_equal(Decimal("1.0"), 1.0)
    assert_equal(Decimal("0.5"), 0.5)
  end

  def test_between
    assert(Decimal(5).between?(Decimal(1), Decimal(10)))
  end

  def test_clamp
    assert_equal(Decimal(3), Decimal(5).clamp(Decimal(1), Decimal(3)))
  end

  def test_clamp_within_range
    assert_equal(Decimal(5), Decimal(5).clamp(Decimal(1), Decimal(10)))
  end
  def test_coerce_integer
    assert_equal(Decimal(7), 5 + Decimal(2))
  end

  def test_coerce_float
    result = 2.0 + Decimal("3")
    assert_instance_of(Float, result)
    assert_in_delta(5.0, result)
  end

  def test_coerce_rational
    assert_equal(Decimal("1.25"), Rational(1, 4) + Decimal(1))
  end

  def test_coerce_unsupported_type
    assert_raise(TypeError) { Decimal(1).coerce("bad") }
  end

  def test_coerce_returns_array
    a, b = Decimal(1).coerce(2)
    assert_instance_of(Decimal, a)
    assert_instance_of(Decimal, b)
  end
  def test_to_f
    result = Decimal("2.5").to_f
    assert_instance_of(Float, result)
    assert_in_delta(2.5, result)
  end

  def test_to_i
    assert_equal(9, Decimal("9.99").to_i)
  end

  def test_to_i_negative
    assert_equal(-3, Decimal("-3.7").to_i)
  end

  def test_to_i_large_bid
    # Near BID significand max (2^51 - 1)
    assert_equal(2251799813685247, Decimal("2251799813685247").to_i)
  end

  def test_to_r
    result = Decimal("0.5").to_r
    assert_instance_of(Rational, result)
    assert_equal(Rational(1, 2), result)
  end

  def test_to_r_large_bid
    assert_equal(Rational(1, 1000000000000000), Decimal("0.000000000000001").to_r)
  end

  def test_to_s
    result = Decimal(100).to_s
    assert_instance_of(String, result)
    assert_equal("100.0", result)
  end

  def test_to_s_fractional
    assert_equal("3.14", Decimal("3.14").to_s)
  end

  def test_to_s_negative
    assert_equal("-42.0", Decimal(-42).to_s)
  end

  def test_inspect
    result = Decimal("1.5").inspect
    assert_instance_of(String, result)
    assert_equal("1.5d", result)
  end

  def test_to_dec
    d = Decimal("3.14")
    assert_same(d, d.to_dec)
  end

  def test_integer_to_dec
    d = 42.to_dec
    assert_instance_of(Decimal, d)
    assert_equal(Decimal(42), d)
  end

  def test_float_to_dec
    d = 42.42.to_dec
    assert_instance_of(Decimal, d)
    assert_equal(Decimal("42.42"), d)
  end

  def test_string_to_dec
    d = "42.42".to_dec
    assert_instance_of(Decimal, d)
    assert_equal(Decimal("42.42"), d)
  end

  def test_scaled_value
    assert_equal(42_420_000_000_000_000_000, Decimal("42.42").scaled_value)
  end

  def test_scaled_value_zero
    assert_equal(0, Decimal(0).scaled_value)
  end

  def test_rational_to_dec
    d = Rational(1, 2).to_dec
    assert_instance_of(Decimal, d)
    assert_equal(Decimal("0.5"), d)
  end

  def test_rational_to_dec_precision_loss
    assert_raise(ArgumentError) { Rational(1, 3).to_dec }
  end
  def test_floor
    assert_equal(3, Decimal("3.7").floor)
  end

  def test_floor_negative
    assert_equal(-4, Decimal("-3.7").floor)
  end

  def test_floor_ndigits
    assert_equal(Decimal("3.1"), Decimal("3.14").floor(1))
  end

  def test_floor_negative_ndigits
    assert_equal(-10, Decimal("-3.7").floor(-1))
  end

  def test_floor_ndigits_identity
    assert_equal(Decimal("3.14"), Decimal("3.14").floor(18))
  end

  def test_ceil
    assert_equal(4, Decimal("3.1").ceil)
  end

  def test_ceil_negative
    assert_equal(-3, Decimal("-3.7").ceil)
  end

  def test_ceil_ndigits
    assert_equal(Decimal("3.2"), Decimal("3.14").ceil(1))
  end

  def test_ceil_exact
    assert_equal(3, Decimal(3).ceil)
  end

  def test_ceil_negative_ndigits
    assert_equal(10, Decimal("3.1").ceil(-1))
  end

  def test_ceil_ndigits_identity
    assert_equal(Decimal("3.14"), Decimal("3.14").ceil(18))
  end

  def test_truncate
    assert_equal(3, Decimal("3.7").truncate)
  end

  def test_truncate_negative
    assert_equal(-3, Decimal("-3.7").truncate)
  end

  def test_truncate_ndigits
    assert_equal(Decimal("3.1"), Decimal("3.14").truncate(1))
  end

  def test_truncate_negative_ndigits
    assert_equal(0, Decimal("3.7").truncate(-1))
  end

  def test_truncate_ndigits_identity
    assert_equal(Decimal("3.14"), Decimal("3.14").truncate(18))
  end

  def test_round
    assert_equal(4, Decimal("3.5").round)
  end

  def test_round_half_up
    assert_equal(4, Decimal("3.5").round(half: :up))
  end

  def test_round_half_down
    assert_equal(3, Decimal("3.5").round(half: :down))
  end

  def test_round_half_even
    assert_equal(4, Decimal("3.5").round(half: :even))
  end

  def test_round_half_even_to_even
    assert_equal(2, Decimal("2.5").round(half: :even))
  end

  def test_round_ndigits
    assert_equal(Decimal("3.1"), Decimal("3.14").round(1))
  end

  def test_round_negative_ndigits
    assert_equal(0, Decimal("3.5").round(-1))
  end

  def test_round_ndigits_identity
    assert_equal(Decimal("3.14"), Decimal("3.14").round(18))
  end

  def test_round_invalid_half
    assert_raise(ArgumentError) { Decimal("3.5").round(half: :bad) }
  end
  def test_zero
    assert_predicate(Decimal(0), :zero?)
  end

  def test_not_zero
    assert_not_predicate(Decimal(1), :zero?)
  end

  def test_positive
    assert_predicate(Decimal(1), :positive?)
  end

  def test_not_positive
    assert_not_predicate(Decimal(-1), :positive?)
  end

  def test_negative
    assert_predicate(Decimal(-1), :negative?)
  end

  def test_not_negative
    assert_not_predicate(Decimal(1), :negative?)
  end

  def test_integer_true
    assert_predicate(Decimal(3), :integer?)
  end

  def test_integer_false
    assert_not_predicate(Decimal("3.14"), :integer?)
  end

  def test_integer_heap
    # Arithmetic on heap decimals produces integral result via dec_from_i128
    d = Decimal("1234567890123456.78") + Decimal("0.22")
    assert_predicate(d, :integer?)
    assert_not_predicate(Decimal("1234567890123456.78"), :integer?)
  end

  def test_abs
    assert_equal(Decimal(42), Decimal(-42).abs)
  end

  def test_abs_positive
    d = Decimal(42)
    assert_same(d, d.abs)
  end

  def test_nonzero
    assert_equal(Decimal(5), Decimal(5).nonzero?)
  end

  def test_nonzero_zero
    assert_nil(Decimal(0).nonzero?)
  end

  def test_frozen
    assert_predicate(Decimal(1), :frozen?)
  end

  def test_frozen_zero
    assert_predicate(Decimal(0), :frozen?)
  end

  def test_is_a_numeric
    assert_kind_of(Numeric, Decimal(1))
  end

  def test_is_a_decimal
    assert_instance_of(Decimal, Decimal(1))
  end

  def test_ractor_shareable
    assert_predicate(Decimal("19.99"), :frozen?)
    assert Ractor.shareable?(Decimal("19.99"))
  end

  def test_finite
    assert_equal(true, Decimal(1).finite?)
    assert_equal(true, Decimal(0).finite?)
    assert_equal(true, Decimal(-1).finite?)
  end

  def test_infinite
    assert_nil(Decimal(1).infinite?)
    assert_nil(Decimal(0).infinite?)
    assert_nil(Decimal(-1).infinite?)
  end
  def test_fix
    assert_equal(Decimal(3), Decimal("3.14").fix)
  end

  def test_fix_negative
    assert_equal(Decimal(-3), Decimal("-3.14").fix)
  end

  def test_frac
    assert_equal(Decimal("0.14"), Decimal("3.14").frac)
  end

  def test_frac_negative
    assert_equal(Decimal("-0.14"), Decimal("-3.14").frac)
  end

  def test_fix_plus_frac
    d = Decimal("3.14")
    assert_equal(d, d.fix + d.frac)
  end

  def test_deconstruct
    assert_equal([3, Decimal("0.14")], Decimal("3.14").deconstruct)
  end

  def test_deconstruct_keys
    assert_equal({whole: 3, frac: Decimal("0.14")},
                 Decimal("3.14").deconstruct_keys(nil))
  end

  def test_deconstruct_keys_selective
    assert_equal({whole: 3}, Decimal("3.14").deconstruct_keys([:whole]))
    assert_equal({frac: Decimal("0.14")}, Decimal("3.14").deconstruct_keys([:frac]))
  end

  def test_pattern_match_hash
    case Decimal("3.14")
    in {whole: Integer => w, frac: Decimal => f}
      assert_equal(3, w)
      assert_instance_of(Decimal, f)
    else
      flunk("pattern match failed")
    end
  end

  def test_pattern_match_array
    case Decimal("3.14")
    in [Integer => w, Decimal => f]
      assert_equal(3, w)
      assert_instance_of(Decimal, f)
    else
      flunk("pattern match failed")
    end
  end
  def test_max
    assert_instance_of(Decimal, Decimal::MAX)
    assert_equal("170141183460469231731.687303715884105727", Decimal::MAX.to_s)
  end

  def test_min
    assert_instance_of(Decimal, Decimal::MIN)
    assert_equal("-170141183460469231731.687303715884105728", Decimal::MIN.to_s)
  end

  def test_precision
    assert_equal(18, Decimal::PRECISION)
  end

  def test_scale
    assert_equal(10**18, Decimal::SCALE)
  end
  def test_marshal_round_trip
    d = Decimal("42.42")
    loaded = Marshal.load(Marshal.dump(d))
    assert_equal(d, loaded)
    assert_instance_of(Decimal, loaded)
    assert_predicate(loaded, :frozen?)
  end

  def test_marshal_round_trip_zero
    d = Decimal(0)
    loaded = Marshal.load(Marshal.dump(d))
    assert_equal(d, loaded)
    assert_instance_of(Decimal, loaded)
  end

  def test_marshal_round_trip_negative
    d = Decimal("-99.5")
    loaded = Marshal.load(Marshal.dump(d))
    assert_equal(d, loaded)
  end

  def test_marshal_does_not_corrupt_zero
    d = Decimal("42.42")
    Marshal.load(Marshal.dump(d))
    assert_equal("0.0", Decimal(0).to_s)
    assert_predicate(Decimal(0), :zero?)
  end
  def test_overflow_add
    assert_raise(RangeError) { Decimal::MAX + Decimal(1) }
  end

  def test_overflow_negate_min
    assert_raise(RangeError) { -Decimal::MIN }
  end

  def test_overflow_sub
    assert_raise(RangeError) { Decimal::MIN - Decimal(1) }
  end

  def test_overflow_mul
    assert_raise(RangeError) { Decimal::MAX * Decimal(2) }
  end

  def test_overflow_min_abs
    assert_raise(RangeError) { Decimal::MIN.abs }
  end

  def test_to_dec_raises_on_invalid
    assert_raise(ArgumentError) { "bad".to_dec }
    assert_raise(ArgumentError) { "42x".to_dec }
  end

  def test_to_dec_exponent
    assert_equal(Decimal(100), "1e2".to_dec)
    assert_equal(Decimal("0.25"), "2.5e-1".to_dec)
  end

  def test_parse_exponent
    assert_equal(Decimal(100), Decimal("1e2"))
    assert_equal(Decimal("1500"), Decimal("1.5e3"))
    assert_equal(Decimal("0.01"), Decimal("1e-2"))
  end

  def test_equality_consistent_with_compare
    assert_equal(0, Decimal("0.5") <=> 0.5)
    assert_equal(Decimal("0.5"), 0.5)
  end

  def test_sort_mixed_numeric
    sorted = [Decimal(3), 1, Decimal("1.5"), Rational(5,2), 2.0].sort
    assert_equal([1, Decimal("1.5"), 2.0, Rational(5,2), Decimal(3)], sorted)
  end

  def test_between_mixed
    assert(Decimal("1.5").between?(1, 2))
    assert(Decimal("1.5").between?(1.0, 2.0))
  end

  def test_clamp_mixed
    assert_equal(1, Decimal("1.5").clamp(0, 1))
    assert_equal(2, Decimal("1.5").clamp(2, 3))
  end

  def test_sum
    result = Array.new(100, Decimal("1.5")).sum(Decimal(0))
    assert_equal(Decimal("150"), result)
  end

  def test_sum_empty
    assert_equal(Decimal(0), [].sum(Decimal(0)))
  end

  def test_sum_integer_init
    result = [Decimal("1.5"), Decimal("2.5")].sum(0)
    assert_equal(Decimal("4"), result)
  end

  def test_sum_mixed_integer_decimal
    result = [1, 2, Decimal("3.5")].sum(Decimal(0))
    assert_equal(Decimal("6.5"), result)
  end

  def test_sum_mixed_float_decimal
    assert_in_delta(3.0, [Decimal(1), 2.0].sum(Decimal(0)))
  end

  def test_parse_precision_loss_raises
    assert_raise(ArgumentError) { Decimal("1.1234567890123456789") }
    assert_nil(Decimal("1.1234567890123456789", exception: false))
  end

  def test_parse_trailing_zeros_ok
    assert_equal(Decimal("1.123456789012345678"), Decimal("1.12345678901234567800"))
  end

  def test_precision_loss_exponent_raises
    assert_raise(ArgumentError) { Decimal("1e-19") }
    assert_nil(Decimal("1e-19", exception: false))
    assert_equal(Decimal("0.000000000000000001"), Decimal("1e-18"))
  end

  def test_precision_loss_rational_raises
    assert_raise(ArgumentError) { Decimal(Rational(1, 10**19)) }
    assert_nil(Decimal(Rational(1, 10**19), exception: false))
    assert_raise(ArgumentError) { Decimal(Rational(1, 3)) }
    assert_equal(Decimal("0.25"), Decimal(Rational(1, 4)))
    assert_equal(Decimal("0.000000000000000001"), Decimal(Rational(1, 10**18)))
  end

  def test_precision_loss_distinct_values
    assert_nil(Decimal("1.1234567890123456785", exception: false))
    assert_nil(Decimal("1.1234567890123456784", exception: false))
  end

  def test_parse_whitespace
    assert_equal(Decimal("42"), Decimal("  42  "))
  end

  def test_parse_empty_raises
    assert_raise(ArgumentError) { Decimal("") }
  end

  def test_parse_empty_exception_false
    assert_nil(Decimal("", exception: false))
  end

  def test_parse_underscores
    assert_equal(Decimal("1000.5"), Decimal("1_000.5"))
    assert_equal(Decimal("1000000.123456"), Decimal("1_000_000.123_456"))
    assert_equal(Decimal("123"), Decimal("1_2_3"))
  end

  def test_parse_rejects_invalid_underscore_placement
    invalid = ["_", "1_", "_1", "1__2", "1._2", "1_.2", "._5", "5._"]

    invalid.each do |value|
      assert_raise(ArgumentError, value) { Decimal(value) }
      assert_nil(Decimal(value, exception: false), value)
    end
  end

  def test_from_nan
    assert_raise(ArgumentError) { Decimal(Float::NAN) }
  end

  def test_from_infinity
    assert_raise(ArgumentError) { Decimal(Float::INFINITY) }
  end

  def test_from_nan_exception_false
    assert_nil(Decimal(Float::NAN, exception: false))
  end

  def test_from_infinity_exception_false
    assert_nil(Decimal(Float::INFINITY, exception: false))
  end

  def test_from_small_float_uses_display_value
    assert_equal(Decimal("0.000001"), Decimal(1e-6))
  end

  def test_from_leading_dot
    assert_equal(Decimal("0.5"), Decimal(".5"))
  end

  def test_from_trailing_dot
    assert_equal(Decimal(5), Decimal("5."))
  end

  def test_from_dot_only
    assert_raise(ArgumentError) { Decimal(".") }
  end

  def test_from_dot_only_exception_false
    assert_nil(Decimal(".", exception: false))
  end
  def test_mul_by_zero
    assert_equal(Decimal(0), Decimal(42) * Decimal(0))
  end

  def test_mul_by_one
    d = Decimal(42)
    assert_same(d, d * Decimal(1))
  end

  def test_div_zero_by_nonzero
    assert_equal(Decimal(0), Decimal(0) / Decimal(42))
  end

  def test_div_by_one
    d = Decimal(42)
    assert_same(d, d / Decimal(1))
  end
  def test_zero_singleton
    assert_same(Decimal(0), Decimal(0))
  end

  def test_negative_zero_string
    assert_same(Decimal(0), Decimal("-0"))
  end

  def test_negative_zero_negate
    assert_same(Decimal(0), -Decimal(0))
  end
  def test_literal_float
    assert_equal Decimal("42.42"), 42.42d
    assert_instance_of Decimal, 42.42d
  end

  def test_literal_integer
    assert_equal Decimal("42"), 42d
    assert_instance_of Decimal, 42d
  end

  def test_literal_zero
    assert_equal Decimal(0), 0.0d
    assert_predicate 0.0d, :zero?
    assert_equal Decimal(0), 0d
    assert_predicate 0d, :zero?
    assert_same 0d, 0.0d
  end

  def test_literal_negative
    assert_equal Decimal("-1.5"), -1.5d
  end

  def test_literal_in_expression
    assert_equal Decimal("3"), 1d + 2d
  end

  def test_literal_underscore
    assert_equal Decimal("1000"), 1_000d
    assert_equal Decimal("1000.5"), 1_000.5d
  end
  def test_ibf_round_trip
    iseq = RubyVM::InstructionSequence.compile("42.42d")
    bin = iseq.to_binary
    loaded = RubyVM::InstructionSequence.load_from_binary(bin)
    assert_equal Decimal("42.42"), loaded.eval
  end

  def test_ibf_round_trip_zero
    iseq = RubyVM::InstructionSequence.compile("0.0d")
    bin = iseq.to_binary
    loaded = RubyVM::InstructionSequence.load_from_binary(bin)
    assert_predicate loaded.eval, :zero?
  end

  def test_ibf_round_trip_negative
    iseq = RubyVM::InstructionSequence.compile("-19.99d")
    bin = iseq.to_binary
    loaded = RubyVM::InstructionSequence.load_from_binary(bin)
    assert_equal Decimal("-19.99"), loaded.eval
  end
  def test_kernel_float
    assert_in_delta(19.99, Float(Decimal("19.99")))
  end

  def test_kernel_integer
    assert_equal(19, Integer(Decimal("19.99")))
  end

  def test_kernel_rational
    assert_equal(Rational(1999, 100), Rational(Decimal("19.99")))
  end

  def test_dup
    d = Decimal("19.99")
    assert_equal(d, d.dup)
  end

  def test_clone
    d = Decimal("19.99")
    assert_equal(d, d.clone)
  end

  def test_clone_freeze_false_raises
    assert_raise(ArgumentError) { Decimal("19.99").clone(freeze: false) }
  end
  def test_string_interpolation
    assert_equal("$19.99", "$#{Decimal("19.99")}")
  end
  def test_heap_arithmetic
    a = Decimal("1234567890123456.78")
    b = Decimal("1.5")
    assert_equal(Decimal("1234567890123458.28"), a + b)
    assert_equal(Decimal("1851851835185185.17"), a * b)
  end

  def test_heap_comparison
    a = Decimal("1234567890123456.78")
    b = Decimal("1234567890123456.79")
    assert_operator(a, :<, b)
    assert_operator(b, :>, a)
    assert_equal(a, a)
  end

  def test_heap_to_s
    assert_equal("1234567890123456.78", Decimal("1234567890123456.78").to_s)
  end

  def test_heap_to_f
    d = Decimal("1234567890123456.78")
    assert_in_delta(1234567890123456.78, d.to_f, 1.0)
  end

  def test_heap_fdiv
    a = Decimal("1234567890123456.78")
    b = Decimal(2)
    assert_in_delta(617283945061728.4, a.fdiv(b), 1.0)
  end

  def test_parse_large_string_does_not_wrap_in_bid_fast_path
    assert_equal("9223372036854775808.1", Decimal("9223372036854775808.1").to_s)
  end

  def test_heap_marshal_round_trip
    d = Decimal("1234567890123456.78")
    loaded = Marshal.load(Marshal.dump(d))
    assert_equal(d, loaded)
  end
end
