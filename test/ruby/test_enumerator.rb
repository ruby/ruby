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
    assert_equal ["x", "y", "z"], enum_test(["z", "y", "x"].each)
    assert_equal [["x", 1], ["y", 2]], enum_test({"y"=>2, "x"=>1})
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
    assert_equal([1, 2, 3], Enumerable::Enumerator.new(@obj, :foo, 1, 2, 3).to_a)
    assert_raise(ArgumentError) { Enumerable::Enumerator.new }
  end

  def test_initialize_copy
    assert_equal([1, 2, 3], @obj.to_enum(:foo, 1, 2, 3).dup.to_a)
    e = @obj.to_enum(:foo, 1, 2, 3)
    assert_nothing_raised { assert_equal(1, e.next) }
    #assert_raise(TypeError) { e.dup }
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
end

