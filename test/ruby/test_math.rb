require 'test/unit'

class TestMath < Test::Unit::TestCase
  def test_math
    assert_equal(2, Math.sqrt(4))

    self.class.class_eval {
      include Math
    }
    assert_equal(2, sqrt(4))
  end
end
