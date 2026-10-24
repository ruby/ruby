# frozen_string_literal: false
require 'test/unit'
require "-test-/bignum"

class TestBignum_Str2big < Test::Unit::TestCase

  SIZEOF_BDIGIT = Bug::Bignum::SIZEOF_BDIGIT
  BITSPERDIG = Bug::Bignum::BITSPERDIG
  BDIGMAX = (1 << BITSPERDIG) - 1

  def test_str2big_poweroftwo
    s = "1" + "0" * 1000
    n = 16 ** 1000
    assert_equal(n, Bug::Bignum.str2big_poweroftwo(s, 16, true))
  end

  def test_str2big_normal
    s = "1" + "0" * 1000
    n = 10 ** 1000
    assert_equal(n, Bug::Bignum.str2big_normal(s, 10, true))
  end

  def test_str2big_normal_digits
    digits = [*"0".."9", *"a".."z"]
    [3, 7, 10, 36].each do |base|
      s = ""
      n = 0
      200.times do |i|
        d = (i * 7 + 1) % base
        s << digits[d]
        n = n * base + d
        assert_equal(n, Bug::Bignum.str2big_normal(s, base, true), "#{s} in base #{base}")
      end
    end
    assert_equal(10**40 + 1, Bug::Bignum.str2big_normal("1" + "_0000" * 9 + "_0001", 10, true))
  end

  def test_str2big_karatsuba
    s = "1" + "0" * 1000
    n = 10 ** 1000
    assert_equal(n, Bug::Bignum.str2big_karatsuba(s, 10, true))
  end

  def test_str2big_gmp
    s = "1" + "0" * 1000
    n = 10 ** 1000
    assert_equal(n, Bug::Bignum.str2big_gmp(s, 10, true))
  rescue NotImplementedError
  end

end
