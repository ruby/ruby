require 'test/unit'

class TestFrozenError < Test::Unit::TestCase
  def test_new_default
    exc = FrozenError.new
    assert_equal("FrozenError", exc.message)
    assert_raise_with_message(ArgumentError, "no receiver is available") {
      exc.receiver
    }
  end

  def test_new_message
    exc = FrozenError.new("bar")
    assert_equal("bar", exc.message)
    assert_raise_with_message(ArgumentError, "no receiver is available") {
      exc.receiver
    }
  end

  def test_new_receiver
    obj = Object.new
    exc = FrozenError.new("bar", receiver: obj)
    assert_equal("bar", exc.message)
    assert_same(obj, exc.receiver)
  end

  def test_message
    obj = Object.new.freeze
    e = assert_raise_with_message(FrozenError, /can't modify frozen #{obj.class}/) {
      obj.instance_variable_set(:@test, true)
    }
    assert_include(e.message, obj.inspect)

    klass = Class.new do
      def init
        @x = true
      end
      def inspect
        init
        super
      end
    end
    obj = klass.new.freeze
    e = assert_raise_with_message(FrozenError, /can't modify frozen #{obj.class}/) {
      obj.init
    }
    assert_include(e.message, klass.inspect)
  end

  def test_receiver
    obj = Object.new.freeze
    e = assert_raise(FrozenError) {def obj.foo; end}
    assert_same(obj, e.receiver)
    e = assert_raise(FrozenError) {obj.singleton_class.const_set(:A, 2)}
    assert_same(obj.singleton_class, e.receiver)
  end
end
