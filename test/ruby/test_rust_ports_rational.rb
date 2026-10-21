# frozen_string_literal: false
require 'test/unit'

# Ruby on Rust: rational.c's fixnum GCD (i_gcd) and its string-scanner
# helpers (issign, read_sign, islettere, isletterr, skip_ws) are ported to
# core_rs/src/rational.rs (port unit rational-A-01).
#
# These tests must pass unchanged in both build modes:
#   ./configure                         (Rust ports, USE_RUST_PORTS=1)
#   ./configure --without-rust-ports    (original C, USE_RUST_PORTS=0)
# Expected values are what the original C implementation produces,
# including its quirks: "1e+" and "1." are accepted by Rational(), while
# "1e3r" and "1e" are not.
class TestRustPortsRational < Test::Unit::TestCase
  # [input, String#to_r, Rational(input), Rational(input, exception: false)]
  CASES = [
    ["", Rational(0, 1), ArgumentError, nil],
    [" ", Rational(0, 1), ArgumentError, nil],
    ["1", Rational(1, 1), Rational(1, 1), Rational(1, 1)],
    ["-1", Rational(-1, 1), Rational(-1, 1), Rational(-1, 1)],
    ["+1", Rational(1, 1), Rational(1, 1), Rational(1, 1)],
    ["--1", Rational(0, 1), ArgumentError, nil],
    ["+-1", Rational(0, 1), ArgumentError, nil],
    ["-", Rational(0, 1), ArgumentError, nil],
    ["+", Rational(0, 1), ArgumentError, nil],
    ["?1", Rational(0, 1), ArgumentError, nil],
    [" \t\n\v\f\r3/4 ", Rational(3, 4), Rational(3, 4), Rational(3, 4)],
    ["\v-7\f", Rational(-7, 1), Rational(-7, 1), Rational(-7, 1)],
    ["1/2\n", Rational(1, 2), Rational(1, 2), Rational(1, 2)],
    ["1 ", Rational(1, 1), Rational(1, 1), Rational(1, 1)],
    # U+00A0 is not ASCII whitespace; its UTF-8 bytes are not isspace().
    ["1 ", Rational(1, 1), ArgumentError, nil],
    [" 1", Rational(0, 1), ArgumentError, nil],
    ["1 /2", Rational(1, 1), ArgumentError, nil],
    ["1/ 2", Rational(1, 1), ArgumentError, nil],
    ["1/3", Rational(1, 3), Rational(1, 3), Rational(1, 3)],
    ["-1/3", Rational(-1, 3), Rational(-1, 3), Rational(-1, 3)],
    ["+2/-3", Rational(2, 1), ArgumentError, nil],
    ["1.5", Rational(3, 2), Rational(3, 2), Rational(3, 2)],
    ["-1.5e3", Rational(-1500, 1), Rational(-1500, 1), Rational(-1500, 1)],
    ["1.5E-3", Rational(3, 2000), Rational(3, 2000), Rational(3, 2000)],
    ["1e", Rational(1, 1), ArgumentError, nil],
    ["1e+", Rational(1, 1), Rational(1, 1), Rational(1, 1)],
    ["1e-", Rational(1, 1), Rational(1, 1), Rational(1, 1)],
    ["1e-2", Rational(1, 100), Rational(1, 100), Rational(1, 100)],
    ["1E+2/3", Rational(100, 3), Rational(100, 3), Rational(100, 3)],
    ["1ee2", Rational(1, 1), ArgumentError, nil],
    ["e5", Rational(0, 1), ArgumentError, nil],
    ["1r", Rational(1, 1), Rational(1, 1), Rational(1, 1)],
    ["1R", Rational(1, 1), Rational(1, 1), Rational(1, 1)],
    ["-3r/4", Rational(-3, 4), Rational(-3, 4), Rational(-3, 4)],
    ["1r/2r", Rational(1, 2), Rational(1, 2), Rational(1, 2)],
    ["2/4r", Rational(1, 2), Rational(1, 2), Rational(1, 2)],
    ["1.5r", Rational(3, 2), Rational(3, 2), Rational(3, 2)],
    ["1e3r", Rational(1000, 1), ArgumentError, nil],
    ["1e2r", Rational(100, 1), ArgumentError, nil],
    ["1re", Rational(1, 1), ArgumentError, nil],
    ["r", Rational(0, 1), ArgumentError, nil],
    ["re", Rational(0, 1), ArgumentError, nil],
    ["1.", Rational(1, 1), Rational(1, 1), Rational(1, 1)],
    [".5", Rational(1, 2), Rational(1, 2), Rational(1, 2)],
    ["1/", Rational(1, 1), ArgumentError, nil],
    ["/2", Rational(0, 1), ArgumentError, nil],
    ["1/2x", Rational(1, 2), ArgumentError, nil],
    ["1_000/2_000", Rational(1, 2), Rational(1, 2), Rational(1, 2)],
    ["1__0", Rational(1, 1), ArgumentError, nil],
    ["1_", Rational(1, 1), ArgumentError, nil],
    ["abc", Rational(0, 1), ArgumentError, nil],
    ["0x10", Rational(0, 1), ArgumentError, nil],
    ["3/0", ZeroDivisionError, ZeroDivisionError, nil],
  ]

  def result
    yield
  rescue ArgumentError, ZeroDivisionError => e
    e.class
  end

  def check(expected, actual, msg)
    if expected.is_a?(Rational)
      assert(expected.eql?(actual), "#{msg}: expected #{expected.inspect}, got #{actual.inspect}")
    else
      assert_equal(expected, actual, msg)
    end
  end

  def test_string_to_r
    CASES.each { |s, lax, _, _| check(lax, result { s.to_r }, "#{s.dump}.to_r") }
  end

  def test_rational_strict
    CASES.each { |s, _, strict, _| check(strict, result { Rational(s) }, "Rational(#{s.dump})") }
  end

  def test_rational_no_exception
    CASES.each { |s, _, _, nx| check(nx, result { Rational(s, exception: false) }, "Rational(#{s.dump}, exception: false)") }
  end

  # The scanner is bounded by the string length, not a NUL terminator.
  def test_embedded_nul
    assert_equal(Rational(1, 1), "1\0/2".to_r)
    assert_raise(ArgumentError) { Rational("1\0") }
    assert_equal(Rational(-3, 1), "-3\0".to_r)
  end

  # i_gcd: Integer#gcd / #lcm on fixnums.
  def test_integer_gcd
    assert_equal(6, 12.gcd(18))
    assert_equal(6, -12.gcd(18))
    assert_equal(6, 12.gcd(-18))
    assert_equal(7, 0.gcd(-7))
    assert_equal(9, -9.gcd(0))
    assert_equal(0, 0.gcd(0))
    assert_equal(1, 17.gcd(5))
    assert_equal(2**40, (2**61).gcd(2**40))
    assert_equal(3, (2**62 - 1).gcd(3))
    assert_equal(2, (-(2**62)).gcd(6))
    assert_equal(85, 17.lcm(5))
    assert_equal([2, 12], 4.gcdlcm(6))
  end

  # i_gcd: Rational normalisation, addition and multiplication of fixnums.
  def test_rational_arithmetic
    assert_equal([2, 3], [Rational(4, 6).numerator, Rational(4, 6).denominator])
    assert_equal(Rational(-3, 2), Rational(-6, 4))
    assert_equal(Rational(0, 1), Rational(0, -5))
    assert_equal(Rational(4, 15), Rational(1, 6) + Rational(1, 10))
    assert_equal(Rational(1, 15), Rational(1, 6) - Rational(1, 10))
    assert_equal(Rational(1, 6), Rational(4, 9) * Rational(3, 8))
    assert_equal(Rational(1, 6), Rational(4, 9) / Rational(8, 3))
    assert_equal(Rational(2**21, 1), Rational(2**61, 2**40))
  end
end
