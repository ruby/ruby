require 'test/unit'
require "-test-/bignum"

class TestBignum < Test::Unit::TestCase
  class TestBig2str < Test::Unit::TestCase

    SIZEOF_BDIGIT = Bignum::SIZEOF_BDIGIT
    BITSPERDIG = Bignum::BITSPERDIG
    BDIGMAX = (1 << BITSPERDIG) - 1

    def test_big2str_generic
      x = 10**1000
      assert_equal("1" + "0" * 1000, x.big2str_generic(10))
    end

    def test_big2str_poweroftwo
      e = BITSPERDIG*2
      x = 0b10**e
      assert_equal("1" + "0" * e, x.big2str_poweroftwo(2))
    end

    def test_big2str_gmp
      x = 10**1000
      assert_equal("1" + "0" * 1000, x.big2str_gmp(10))
    rescue NotImplementedError
    end

  end
end
