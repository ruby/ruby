# frozen_string_literal: false
require 'test/unit'
require "-test-/rational"

class TestRational < Test::Unit::TestCase
  class TestGCD < Test::Unit::TestCase

    def test_gcd_normal
      x = 2*2*3*3*3
      y = 2*2*2*3*3
      gcd = 2*2*3*3
      assert_equal(gcd, x.gcd_normal(y))
    end

    def test_gcd_gmp
      x = 2*2*3*3*3
      y = 2*2*2*3*3
      gcd = 2*2*3*3
      assert_equal(gcd, x.gcd_gmp(y))
    rescue NotImplementedError
    end

    def test_gcd_gmp_brute_force
      -13.upto(13) {|x|
        -13.upto(13) {|y|
          assert_equal(x.gcd_normal(y), x.gcd_gmp(y))
        }
      }
    rescue NotImplementedError
    end
  end

  def test_rb_rational_raw
    rat = Rational.raw(1, 2)
    assert_equal(1, rat.numerator)
    assert_equal(2, rat.denominator)

    rat = Rational.raw(-1, 2)
    assert_equal(-1, rat.numerator)
    assert_equal(2, rat.denominator)

    rat = Rational.raw(1, -2)
    assert_equal(-1, rat.numerator)
    assert_equal(2, rat.denominator)

    assert_equal(1/2r, Rational.raw(1.0, 2.0))

    assert_raise(TypeError) { Rational.raw("1", 2) }
    assert_raise(TypeError) { Rational.raw(1, "2") }

    class << (o = Object.new)
      def to_i; 42; end
    end

    assert_raise(TypeError) { Rational.raw(o, 2) }
    assert_raise(TypeError) { Rational.raw(1, o) }

    class << (o = Object.new)
      def to_int; 42; end
    end

    rat = Rational.raw(o, 2)
    assert_equal(42, rat.numerator)
    assert_equal(2, rat.denominator)

    rat = Rational.raw(2, o)
    assert_equal(2, rat.numerator)
    assert_equal(42, rat.denominator)
  end
end
