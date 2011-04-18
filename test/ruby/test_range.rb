require 'test/unit'

class TestRange < Test::Unit::TestCase
  def test_range_string
    # XXX: Is this really the test of Range?
    assert_equal([], ("a" ... "a").to_a)
    assert_equal(["a"], ("a" .. "a").to_a)
    assert_equal(["a"], ("a" ... "b").to_a)
    assert_equal(["a", "b"], ("a" .. "b").to_a)
  end

  def test_evaluation_order
    arr = [1,2]
    r = (arr.shift)..(arr.shift)
    assert_equal(1..2, r, "[ruby-dev:26383]")
  end

  def test_step_ruby_core_35753
    assert_equal(6, (1...6.3).step.to_a.size)
    assert_equal(5, (1.1...6).step.to_a.size)
    assert_equal(5, (1...6).step(1.1).to_a.size)
    assert_equal(3, (1.0...6.3).step(1.8).to_a.size)
    assert_equal(3, (1.0...6.4).step(1.8).to_a.size)
    assert_equal(4, (1.0...6.5).step(1.8).to_a.size)
  end
end
