# frozen_string_literal: false
require 'test/unit'
require "-test-/bignum"

class TestBignum_Big2str < Test::Unit::TestCase

  SIZEOF_BDIGIT = Bug::Bignum::SIZEOF_BDIGIT
  BITSPERDIG = Bug::Bignum::BITSPERDIG
  BDIGMAX = (1 << BITSPERDIG) - 1

  def test_big2str_generic
    x = 10**1000
    assert_equal("1" + "0" * 1000, Bug::Bignum.big2str_generic(x, 10))
  end

  def test_big2str_poweroftwo
    e = BITSPERDIG*2
    x = 0b10**e
    assert_equal("1" + "0" * e, Bug::Bignum.big2str_poweroftwo(x, 2))
  end

  def test_big2str_gmp
    x = 10**1000
    assert_equal("1" + "0" * 1000, Bug::Bignum.big2str_gmp(x, 10))
  end

end
