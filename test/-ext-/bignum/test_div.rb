# frozen_string_literal: false
require 'test/unit'
require "-test-/bignum"

class TestBignum_Div < Test::Unit::TestCase

  SIZEOF_BDIGIT = Bug::Bignum::SIZEOF_BDIGIT
  BITSPERDIG = Bug::Bignum::BITSPERDIG
  BDIGMAX = (1 << BITSPERDIG) - 1

  TESTCASE_SMALL = [(1 << (BITSPERDIG*2)) | (2 << BITSPERDIG) | 3, (1 << BITSPERDIG) | 1, (1 << BITSPERDIG) | 1, 2]
  TESTCASE_LARGE_YQR = [(7**1000) * (5**1000) + (3**1000), 7**1000, 5**1000, 3**1000]
  TESTCASE_LARGE_Y = [(7**1000) * ((1 << BITSPERDIG) | 1) + BDIGMAX, 7**1000, (1 << BITSPERDIG) | 1, BDIGMAX]
  TESTCASE_LARGE_Q = [((1 << BITSPERDIG) | 1) * (5**1000) + BDIGMAX, (1 << BITSPERDIG) | 1, 5**1000, BDIGMAX]
  TESTCASES = [TESTCASE_SMALL, TESTCASE_LARGE_YQR, TESTCASE_LARGE_Q, TESTCASE_LARGE_Y]

  def test_divrem_normal
    TESTCASES.each do |x, y, q, r|
      assert_equal([q, r], Bug::Bignum.big_divrem_normal(x, y))
    end
  end

  def test_divrem_newton_raphson
    TESTCASES.each do |x, y, q, r|
      assert_equal([q, r], Bug::Bignum.big_divrem_newton_raphson(x, y))
    end
  end

  def test_divrem_gmp
    TESTCASES.each do |x, y, q, r|
      assert_equal([q, r], Bug::Bignum.big_divrem_gmp(x, y))
    end
  rescue NotImplementedError
  end
end
