require 'test/unit'

class TestEnumerator < Test::Unit::TestCase
  def setup
    @obj = Object.new
    class << @obj
      include Enumerable
      def foo(*a)
        a.each {|x| yield x }
      end
    end
  end

  def enum_test obj
    i = 0
    obj.map{|e|
      e
    }.sort
  end

  def test_iterators
    assert_equal [0, 1, 2], enum_test(3.times)
    assert_equal [:x, :y, :z], enum_test([:x, :y, :z].each)
    assert_equal [[:x, 1], [:y, 2]], enum_test({:x=>1, :y=>2})
  end

  ## Enumerator as Iterator

  def test_next
    e = 3.times
    3.times{|i|
      assert_equal i, e.next
    }
    assert_raise(StopIteration){e.next}
  end

  def test_loop
    e = 3.times
    i = 0
    loop{
      assert_equal(i, e.next)
      i += 1
    }
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


  def test_initialize
    assert_equal([1, 2, 3], @obj.to_enum(:foo, 1, 2, 3).to_a)
    assert_equal([1, 2, 3], Enumerator.new(@obj, :foo, 1, 2, 3).to_a)
    assert_equal([1, 2, 3], Enumerator.new { |y| i = 0; loop { y << (i += 1) } }.take(3))
    assert_raise(ArgumentError) { Enumerator.new }
  end

  def test_initialize_copy
    assert_equal([1, 2, 3], @obj.to_enum(:foo, 1, 2, 3).dup.to_a)
    e = @obj.to_enum(:foo, 1, 2, 3)
    assert_nothing_raised { assert_equal(1, e.next) }
    assert_raise(TypeError) { e.dup }

    e = Enumerator.new { |y| i = 0; loop { y << (i += 1) } }.dup
    assert_nothing_raised { assert_equal(1, e.next) }
    assert_raise(TypeError) { e.dup }
  end

  def test_gc
    assert_nothing_raised do
      1.times do
        foo = [1,2,3].to_enum
        GC.start
      end
      GC.start
    end
  end

  def test_slice
    assert_equal([[1,2,3],[4,5,6],[7,8,9],[10]], (1..10).each_slice(3).to_a)
  end

  def test_cons
    a = [[1,2,3], [2,3,4], [3,4,5], [4,5,6], [5,6,7], [6,7,8], [7,8,9], [8,9,10]]
    assert_equal(a, (1..10).each_cons(3).to_a)
  end

  def test_with_index
    assert_equal([[1,0],[2,1],[3,2]], @obj.to_enum(:foo, 1, 2, 3).with_index.to_a)
    assert_equal([[1,5],[2,6],[3,7]], @obj.to_enum(:foo, 1, 2, 3).with_index(5).to_a)
  end

  def test_with_object
    obj = [0, 1]
    ret = (1..10).each.with_object(obj) {|i, memo|
      memo[0] += i
      memo[1] *= i
    }
    assert_same(obj, ret)
    assert_equal([55, 3628800], ret)

    a = [2,5,2,1,5,3,4,2,1,0]
    obj = {}
    ret = a.delete_if.with_object(obj) {|i, seen|
      if seen.key?(i)
        true
      else
        seen[i] = true
        false
      end
    }
    assert_same(obj, ret)
    assert_equal([2, 5, 1, 3, 4, 0], a)
  end

  def test_next_rewind
    e = @obj.to_enum(:foo, 1, 2, 3)
    assert_equal(1, e.next)
    assert_equal(2, e.next)
    e.rewind
    assert_equal(1, e.next)
    assert_equal(2, e.next)
    assert_equal(3, e.next)
    assert_raise(StopIteration) { e.next }
  end

  def test_peek
    a = [1]
    e = a.each
    assert_equal(1, e.peek)
    assert_equal(1, e.peek)
    assert_equal(1, e.next)
    assert_raise(StopIteration) { e.peek }
    assert_raise(StopIteration) { e.peek }
  end

  def test_next_after_stopiteration
    a = [1]
    e = a.each
    assert_equal(1, e.next)
    assert_raise(StopIteration) { e.next }
    assert_raise(StopIteration) { e.next }
    e.rewind
    assert_equal(1, e.next)
    assert_raise(StopIteration) { e.next }
    assert_raise(StopIteration) { e.next }
  end
end

