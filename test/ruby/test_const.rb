require 'test/unit'

$KCODE = 'none'

class TestConst < Test::Unit::TestCase
  TEST1 = 1
  TEST2 = 2
    
  module Const
    TEST3 = 3
    TEST4 = 4
  end
    
  module Const2
    TEST3 = 6
    TEST4 = 8
  end
    
  def test_const
    self.class.class_eval {
      include Const
    }
    assert_equal([TEST1,TEST2,TEST3,TEST4], [1,2,3,4])
    
    self.class.class_eval {
      include Const2
    }
    STDERR.print "intentionally redefines TEST3, TEST4\n" if $VERBOSE
    assert_equal([TEST1,TEST2,TEST3,TEST4], [1,2,6,8])
    
    assert_equal((String <=> Object), -1)
    assert_equal((Object <=> String), 1)
    assert_equal((Array <=> String), nil)
  end
end
