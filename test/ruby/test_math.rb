require 'test/unit'

$KCODE = 'none'

class TestMath < Test::Unit::TestCase
  def test_math
    assert(Math.sqrt(4) == 2)
    
    self.class.class_eval {
      include Math
    }
    assert(sqrt(4) == 2)
  end
end
