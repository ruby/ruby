# frozen_string_literal: true
require_relative 'test_helper'
begin
  require 'bigdecimal'
rescue LoadError
end

class JSONRyuFallbackTest < Test::Unit::TestCase
  include JSON

  # Test that numbers with more than 17 significant digits fall back to rb_cstr_to_dbl
  def test_more_than_17_significant_digits
    # These numbers have > 17 significant digits and should use fallback path
    # They should still parse correctly, just not via the Ryu optimization

    test_cases = [
      # input, expected (rounded to double precision)
      ["1.23456789012345678901234567890", 1.2345678901234567],
      ["123456789012345678.901234567890", 1.2345678901234568e+17],
      ["0.123456789012345678901234567890", 0.12345678901234568],
      ["9999999999999999999999999999.9", 1.0e+28],
      # Edge case: exactly 18 digits
      ["123456789012345678", 123456789012345680.0],
      # Many fractional digits
      ["0.12345678901234567890123456789", 0.12345678901234568],
    ]

    test_cases.each do |input, expected|
      result = JSON.parse(input)
      assert_in_delta(expected, result, 1e-10,
        "Failed to parse #{input} correctly (>17 digits, fallback path)")
    end
  end

  # Test decimal_class option forces fallback
  def test_decimal_class_option
    input = "3.141"

    # Without decimal_class: uses Ryu, returns Float
    result_float = JSON.parse(input)
    assert_instance_of(Float, result_float)
    assert_equal(3.141, result_float)

    # With decimal_class: uses fallback, returns BigDecimal
    result_bigdecimal = JSON.parse(input, decimal_class: BigDecimal)
    assert_instance_of(BigDecimal, result_bigdecimal)
    assert_equal(BigDecimal("3.141"), result_bigdecimal)
  end if defined?(::BigDecimal)

  # Test that numbers with <= 17 digits use Ryu optimization
  def test_ryu_optimization_used_for_normal_numbers
    test_cases = [
      ["3.141", 3.141],
      ["1.23456789012345e100", 1.23456789012345e100],
      ["0.00000000000001", 1.0e-14],
      ["123456789012345.67", 123456789012345.67],
      ["-1.7976931348623157e+308", -1.7976931348623157e+308],
      ["2.2250738585072014e-308", 2.2250738585072014e-308],
      # Exactly 17 significant digits
      ["12345678901234567", 12345678901234567.0],
      ["1.2345678901234567", 1.2345678901234567],
    ]

    test_cases.each do |input, expected|
      result = JSON.parse(input)
      assert_in_delta(expected, result, expected.abs * 1e-15,
        "Failed to parse #{input} correctly (<=17 digits, Ryu path)")
    end
  end

  # Test edge cases at the boundary (17 digits)
  def test_seventeen_digit_boundary
    # Exactly 17 significant digits should use Ryu
    input_17 = "12345678901234567.0"  # Force it to be a float with .0
    result = JSON.parse(input_17)
    assert_in_delta(12345678901234567.0, result, 1e-10)

    # 18 significant digits should use fallback
    input_18 = "123456789012345678.0"
    result = JSON.parse(input_18)
    # Note: This will be rounded to double precision
    assert_in_delta(123456789012345680.0, result, 1e-10)
  end

  # Test that leading zeros don't count toward the 17-digit limit
  def test_leading_zeros_dont_count
    test_cases = [
      ["0.00012345678901234567", 0.00012345678901234567],  # 17 significant digits
      ["0.000000000000001234567890123456789", 1.234567890123457e-15],  # >17 significant
    ]

    test_cases.each do |input, expected|
      result = JSON.parse(input)
      assert_in_delta(expected, result, expected.abs * 1e-10,
        "Failed to parse #{input} correctly")
    end
  end

  # Test that Ryu handles special values correctly
  def test_special_double_values
    test_cases = [
      ["1.7976931348623157e+308", Float::MAX],  # Largest finite double
      ["2.2250738585072014e-308", Float::MIN],  # Smallest normalized double
    ]

    test_cases.each do |input, expected|
      result = JSON.parse(input)
      assert_in_delta(expected, result, expected.abs * 1e-10,
        "Failed to parse #{input} correctly")
    end

    # Test zero separately
    result_pos_zero = JSON.parse("0.0")
    assert_equal(0.0, result_pos_zero)

    # Note: JSON.parse doesn't preserve -0.0 vs +0.0 distinction in standard mode
    result_neg_zero = JSON.parse("-0.0")
    assert_equal(0.0, result_neg_zero.abs)
  end

  # Test subnormal numbers that caused precision issues before fallback was added
  # These are extreme edge cases discovered by fuzzing (4 in 6 billion numbers tested)
  def test_subnormal_edge_cases_round_trip
    # These subnormal numbers (~1e-310) had 1 ULP rounding errors in original Ryu
    # They now use rb_cstr_to_dbl fallback for exact precision
    test_cases = [
      "-3.2652630314355e-310",
      "3.9701623107025e-310",
      "-3.6607772435415e-310",
      "2.9714076801985e-310",
    ]

    test_cases.each do |input|
      # Parse the number
      result = JSON.parse(input)

      # Should be bit-identical
      assert_equal(result, JSON.parse(result.to_s),
        "Subnormal #{input} failed round-trip test")

      # Should be bit-identical
      assert_equal(result, JSON.parse(JSON.dump(result)),
        "Subnormal #{input} failed round-trip test")

      # Verify the value is in the expected subnormal range
      assert(result.abs < 2.225e-308,
        "#{input} should be subnormal (< 2.225e-308)")
    end
  end

  # Test invalid numbers are properly rejected
  def test_invalid_numbers_rejected
    invalid_cases = [
      "-",
      ".",
      "-.",
      "-.e10",
      "1.2.3",
      "1e",
      "1e+",
    ]

    invalid_cases.each do |input|
      assert_raise(JSON::ParserError, "Should reject invalid number: #{input}") do
        JSON.parse(input)
      end
    end
  end
end
