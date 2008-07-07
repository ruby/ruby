require 'test/unit'

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
    assert_equal([1,2,3,4], [TEST1,TEST2,TEST3,TEST4])

    self.class.class_eval {
      include Const2
    }
    STDERR.print "intentionally redefines TEST3, TEST4\n" if $VERBOSE
    assert_equal([1,2,6,8], [TEST1,TEST2,TEST3,TEST4])

    assert_equal(-1, (String <=> Object))
    assert_equal(1, (Object <=> String))
    assert_equal(nil, (Array <=> String))
  end
end
