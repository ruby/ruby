require 'test/unit'

class TestEnumerator < Test::Unit::TestCase
  def enum_test obj
    i = 0
    obj.map{|e|
      [i+=1, e]
    }
  end

  def test_iterators
    assert_equal [[1, 0], [2, 1], [3, 2]], enum_test(3.times)
    assert_equal [[1, :x], [2, :y], [3, :z]], enum_test([:x, :y, :z].each)
    assert_equal [[1, [:x, 1]], [2, [:y, 2]]], enum_test({:x=>1, :y=>2})
  end

  ## Enumerator as Iterator

  def test_next
    e = 3.times
    3.times{|i|
      assert_equal i, e.next
    }
    assert_raise(StopIteration){e.next}
  end

  def test_next?
    e = 3.times
    assert_equal true, e.next?
    3.times{|i|
      assert_equal true, e.next?
      assert_equal i, e.next
    }
    assert_equal false, e.next?
  end

  def test_nested_itaration
    def (o = Object.new).each
      yield :ok1
      yield [:ok2, :x].each.next
    end
    e = o.to_enum
    assert_equal :ok1, e.next
    assert_equal :ok2, e.next
    assert_raise(StopIteration){e.next}
  end
end

