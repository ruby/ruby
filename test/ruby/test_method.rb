require 'test/unit'

class TestMethod < Test::Unit::TestCase
  def m0() end
  def m1(a) end
  def m2(a, b) end
  def mo1(a = nil, &b) end
  def mo2(a, b = nil) end
  def mo3(*a) end
  def mo4(a, *b, &c) end
  def mo5(a, *b, c) end
  def mo6(a, *b, c, &d) end

  class Base
    def foo() :base end
  end
  class Derived < Base
    def foo() :derived end
  end

  def test_arity
    assert_equal(0, method(:m0).arity)
    assert_equal(1, method(:m1).arity)
    assert_equal(2, method(:m2).arity)
    assert_equal(-1, method(:mo1).arity)
    assert_equal(-2, method(:mo2).arity)
    assert_equal(-1, method(:mo3).arity)
    assert_equal(-2, method(:mo4).arity)
    assert_equal(-3, method(:mo5).arity)
    assert_equal(-3, method(:mo6).arity)
  end

  def test_unbind
    assert_equal(:derived, Derived.new.foo)
    um = Derived.new.method(:foo).unbind
    assert_instance_of(UnboundMethod, um)
    Derived.class_eval do
      def foo() :changed end
    end
    assert_equal(:changed, Derived.new.foo)
    assert_equal(:derived, um.bind(Derived.new).call)
    assert_raise(TypeError) do
      um.bind(Base.new)
    end
  end

  def test_callee
    assert_equal(:test_callee, __method__)
    assert_equal(:m, Class.new {def m; __method__; end}.new.m)
    assert_equal(:m, Class.new {def m; tap{return __method__}; end}.new.m)
    assert_equal(:m, Class.new {define_method(:m) {__method__}}.new.m)
    assert_equal(:m, Class.new {define_method(:m) {tap{return __method__}}}.new.m)
    assert_nil(eval("class TestCallee; __method__; end"))
  end
end
