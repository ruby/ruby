require_relative "testbase"

require 'bigdecimal/util'

class TestBigDecimalUtil < Test::Unit::TestCase
  def test_BigDecimal_to_d
    x = BigDecimal(1)
    assert_same(x, x.to_d)
  end
end
