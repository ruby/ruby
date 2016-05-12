# frozen_string_literal: false
require 'test/unit'
require "-test-/bignum"

class TestBignum < Test::Unit::TestCase
  class TestMul < Test::Unit::TestCase

    SIZEOF_BDIGIT = Bignum::SIZEOF_BDIGIT
    BITSPERDIG = Bignum::BITSPERDIG
    BDIGMAX = (1 << BITSPERDIG) - 1

    def test_mul_normal
      x = (1 << BITSPERDIG) | 1
      y = (1 << BITSPERDIG) | 1
      z = (1 << (BITSPERDIG*2)) | (2 << BITSPERDIG) | 1
      assert_equal(z, x.big_mul_normal(y))
    end

    def test_mul_normal_zero_in_x
      x = (1 << (2*BITSPERDIG)) | 1
      y = (1 << BITSPERDIG) | 1
      z = (1 << (BITSPERDIG*3)) | (1 << (BITSPERDIG*2)) | (1 << BITSPERDIG) | 1
      assert_equal(z, x.big_mul_normal(y))
    end

    def test_mul_normal_zero_in_y
      x = (1 << BITSPERDIG) | 1
      y = (1 << (2*BITSPERDIG)) | 1
      z = (1 << (BITSPERDIG*3)) | (1 << (BITSPERDIG*2)) | (1 << BITSPERDIG) | 1
      assert_equal(z, x.big_mul_normal(y))
    end

    def test_mul_normal_max_max
      x = (1 << (2*BITSPERDIG)) - 1
      y = (1 << (2*BITSPERDIG)) - 1
      z = (1 << (4*BITSPERDIG)) - (1 << (2*BITSPERDIG+1)) + 1
      assert_equal(z, x.big_mul_normal(y))
    end

    def test_sq_fast
      x = (1 << BITSPERDIG) | 1
      z = (1 << 2*BITSPERDIG) | (2 << BITSPERDIG) | 1
      assert_equal(z, x.big_sq_fast)
    end

    def test_sq_fast_max2
      x = (BDIGMAX << BITSPERDIG) | BDIGMAX
      assert_equal(x.big_mul_normal(x), x.big_sq_fast)
    end

    def test_sq_fast_zero_in_middle
      x = (BDIGMAX << 2*BITSPERDIG) | BDIGMAX
      assert_equal(x.big_mul_normal(x), x.big_sq_fast)
    end

    def test_mul_balance
      x = (1 << BITSPERDIG) | 1
      y = (1 << BITSPERDIG) | 1
      z = (1 << (BITSPERDIG*2)) | (2 << BITSPERDIG) | 1
      assert_equal(z, x.big_mul_balance(y))
    end

    def test_mul_balance_2x16
      x = (1 << Bignum::BITSPERDIG) | 1
      y = (1 << Bignum::BITSPERDIG*16) | 1
      assert_equal(x.big_mul_normal(y), x.big_mul_balance(y))
    end

    def test_mul_balance_2x17
      x = (1 << Bignum::BITSPERDIG) | 1
      y = (1 << Bignum::BITSPERDIG*17) | 1
      assert_equal(x.big_mul_normal(y), x.big_mul_balance(y))
    end

    def test_mul_karatsuba
      x = (1 << BITSPERDIG) | 1
      y = (1 << BITSPERDIG) | 1
      z = (1 << (BITSPERDIG*2)) | (2 << BITSPERDIG) | 1
      assert_equal(z, x.big_mul_karatsuba(y))
    end

    def test_mul_karatsuba_odd_y
      x = (1 << BITSPERDIG) | 1
      y = (1 << (2*BITSPERDIG)) | 1
      assert_equal(x.big_mul_normal(y), x.big_mul_karatsuba(y))
    end

    def test_mul_karatsuba_odd_xy
      x = (1 << (2*BITSPERDIG)) | 1
      y = (1 << (2*BITSPERDIG)) | 1
      assert_equal(x.big_mul_normal(y), x.big_mul_karatsuba(y))
    end

    def test_mul_karatsuba_x1_gt_x0
      x = (2 << BITSPERDIG) | 1
      y = (1 << BITSPERDIG) | 2
      assert_equal(x.big_mul_normal(y), x.big_mul_karatsuba(y))
    end

    def test_mul_karatsuba_y1_gt_y0
      x = (1 << BITSPERDIG) | 2
      y = (2 << BITSPERDIG) | 1
      assert_equal(x.big_mul_normal(y), x.big_mul_karatsuba(y))
    end

    def test_mul_karatsuba_x1_gt_x0_and_y1_gt_y0
      x = (2 << BITSPERDIG) | 1
      y = (2 << BITSPERDIG) | 1
      assert_equal(x.big_mul_normal(y), x.big_mul_karatsuba(y))
    end

    def test_mul_karatsuba_carry2
      x = (1 << BITSPERDIG) | BDIGMAX
      y = (1 << BITSPERDIG) | BDIGMAX
      assert_equal(x.big_mul_normal(y), x.big_mul_karatsuba(y))
    end

    def test_mul_karatsuba_borrow
      x = (BDIGMAX << BITSPERDIG) | 1
      y = (BDIGMAX << BITSPERDIG) | 1
      assert_equal(x.big_mul_normal(y), x.big_mul_karatsuba(y))
    end

    def test_mul_toom3
      x = (1 << 2*BITSPERDIG) | (1 << BITSPERDIG) | 1
      y = (1 << 2*BITSPERDIG) | (1 << BITSPERDIG) | 1
      assert_equal(x.big_mul_normal(y), x.big_mul_toom3(y))
    end

    def test_mul_gmp
      x = (1 << 2*BITSPERDIG) | (1 << BITSPERDIG) | 1
      y = (1 << 2*BITSPERDIG) | (1 << BITSPERDIG) | 1
      assert_equal(x.big_mul_normal(y), x.big_mul_gmp(y))
    rescue NotImplementedError
    end

  end
end
