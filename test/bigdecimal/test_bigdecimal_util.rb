require_relative "testbase"

require 'bigdecimal/util'

class TestBigDecimalUtil < Test::Unit::TestCase
  def test_BigDecimal_to_d
    x = BigDecimal(1)
    assert_same(x, x.to_d)
  end

  def test_Integer_to_d
    assert_equal(BigDecimal(1), 1.to_d)
    assert_equal(BigDecimal(2<<100), (2<<100).to_d)
  end
end
