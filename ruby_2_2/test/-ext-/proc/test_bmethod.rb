require 'test/unit'
require '-test-/proc'

class TestProc < Test::Unit::TestCase
  class TestBMethod < Test::Unit::TestCase
  end
end

class TestProc::TestBMethod
  class Base
    def foo(*a)
      a
    end
  end

  class Bound < Base
    define_method(:foo, Bug::Proc.make_call_super(42))
    define_method(:receiver, Bug::Proc.make_call_receiver(nil))
  end

  def test_super_in_bmethod
    obj = Bound.new
    assert_equal([1, 42], obj.foo(1))
  end

  def test_block_super
    obj = Bound.new
    result = nil
    obj.foo(2) {|*a| result = a}
    assert_equal([2, 42], result)
  end

  def test_receiver_in_bmethod
    obj = Bound.new
    assert_same(obj, obj.receiver)
  end
end
