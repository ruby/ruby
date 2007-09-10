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

  class DuckRange
    def initialize(b,e,excl=false)
      @begin = b
      @end = e
      @excl = excl
    end
    attr_reader :begin, :end

    def exclude_end?
      @excl
    end
  end

  def test_duckrange
    assert_equal("bc", "abcd"[DuckRange.new(1,2)])
  end

  def test_min
    assert_equal(1, (1..2).min)
    assert_equal(nil, (2..1).min)
    assert_equal(1, (1...2).min)

    assert_equal(1.0, (1.0..2.0).min)
    assert_equal(nil, (2.0..1.0).min)
    assert_equal(1, (1.0...2.0).min)

    assert_equal(0, (0..0).min)
    assert_equal(nil, (0...0).min)
  end

  def test_max
    assert_equal(2, (1..2).max)
    assert_equal(nil, (2..1).max)
    assert_equal(1, (1...2).max)

    assert_equal(2.0, (1.0..2.0).max)
    assert_equal(nil, (2.0..1.0).max)
    assert_raise(TypeError) { (1.0...2.0).max }

    assert_equal(-0x80000002, ((-0x80000002)...(-0x80000001)).max)

    assert_equal(0, (0..0).max)
    assert_equal(nil, (0...0).max)
  end

  def test_initialize_twice
    r = eval("1..2")
    assert_raise(NameError) { r.instance_eval { initialize 3, 4 } }
  end
end
