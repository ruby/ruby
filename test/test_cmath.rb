require 'test/unit'
require 'cmath'

class TestCMath < Test::Unit::TestCase
  def test_sqrt
    assert_equal CMath.sqrt(1.0.i), CMath.sqrt(1.i), '[ruby-core:31672]'
  end
end
