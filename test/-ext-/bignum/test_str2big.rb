# frozen_string_literal: false
require 'test/unit'
require "-test-/bignum"

class TestBignum < Test::Unit::TestCase
  class TestStr2big < Test::Unit::TestCase

    SIZEOF_BDIGIT = Bignum::SIZEOF_BDIGIT
    BITSPERDIG = Bignum::BITSPERDIG
    BDIGMAX = (1 << BITSPERDIG) - 1

    def test_str2big_poweroftwo
      s = "1" + "0" * 1000
      n = 16 ** 1000
      assert_equal(n, s.str2big_poweroftwo(16, true))
    end

    def test_str2big_normal
      s = "1" + "0" * 1000
      n = 10 ** 1000
      assert_equal(n, s.str2big_normal(10, true))
    end

    def test_str2big_karatsuba
      s = "1" + "0" * 1000
      n = 10 ** 1000
      assert_equal(n, s.str2big_karatsuba(10, true))
    end

    def test_str2big_gmp
      s = "1" + "0" * 1000
      n = 10 ** 1000
      assert_equal(n, s.str2big_gmp(10, true))
    rescue NotImplementedError
    end

  end
end
