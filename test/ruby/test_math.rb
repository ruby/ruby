require 'test/unit'

$KCODE = 'none'

class TestMath < Test::Unit::TestCase
  def test_math
    assert_equal(Math.sqrt(4), 2)
    
    self.class.class_eval {
      include Math
    }
    assert_equal(sqrt(4), 2)
  end
end
