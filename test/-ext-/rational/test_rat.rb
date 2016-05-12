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
end
