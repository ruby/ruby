require 'test/unit'
require_relative 'envutil'

class TestMethod < Test::Unit::TestCase
  def setup
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  def teardown
    $VERBOSE = @verbose
  end

  def ruby(*r, &b)
    EnvUtil.rubyexec(*r, &b)
  end

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

  def test_body
    o = Object.new
    def o.foo; end
    assert_nothing_raised { RubyVM::InstructionSequence.disasm(o.method(:foo)) }
  end

  def test_new
    c1 = Class.new
    c1.class_eval { def foo; :foo; end }
    c2 = Class.new(c1)
    c2.class_eval { private :foo }
    o = c2.new
    o.extend(Module.new)
    assert_raise(NameError) { o.method(:bar) }
    assert_raise(NameError) { o.public_method(:foo) }
    assert_equal(:foo, o.method(:foo).call)
  end

  def test_eq
    o = Object.new
    class << o
      def foo; end
      alias bar foo
      def baz; end
    end
    assert_not_equal(o.method(:foo), nil)
    m = o.method(:foo)
    def m.foo; end
    assert_not_equal(o.method(:foo), m)
    assert_equal(o.method(:foo), o.method(:foo))
    assert_equal(o.method(:foo), o.method(:bar))
    assert_not_equal(o.method(:foo), o.method(:baz))
  end

  def test_hash
    o = Object.new
    def o.foo; end
    assert_kind_of(Integer, o.method(:foo).hash)
  end

  def test_receiver_name_owner
    o = Object.new
    def o.foo; end
    m = o.method(:foo)
    assert_equal(o, m.receiver)
    assert_equal(:foo, m.name)
    assert_equal(class << o; self; end, m.owner)
    assert_equal(:foo, m.unbind.name)
    assert_equal(class << o; self; end, m.unbind.owner)
  end

  def test_instance_method
    c = Class.new
    c.class_eval do
      def foo; :foo; end
      private :foo
    end
    o = c.new
    o.method(:foo).unbind
    assert_raise(NoMethodError) { o.foo }
    c.instance_method(:foo).bind(o)
    assert_equal(:foo, o.instance_eval { foo })
    assert_raise(NameError) { c.public_instance_method(:foo) }
    def o.bar; end
    m = o.method(:bar).unbind
    assert_raise(TypeError) { m.bind(Object.new) }
  end

  def test_define_method
    c = Class.new
    c.class_eval { def foo; :foo; end }
    o = c.new
    def o.bar; :bar; end
    assert_raise(TypeError) do
      c.class_eval { define_method(:foo, :foo) }
    end
    assert_raise(ArgumentError) do
      c.class_eval { define_method }
    end
    c2 = Class.new(c)
    c2.class_eval { define_method(:baz, o.method(:foo)) }
    assert_equal(:foo, c2.new.baz)
    assert_raise(TypeError) do
      Class.new.class_eval { define_method(:foo, o.method(:foo)) }
    end
    assert_raise(TypeError) do
      Class.new.class_eval { define_method(:bar, o.method(:bar)) }
    end

    o = Object.new
    def o.foo(c)
      c.class_eval { define_method(:foo) }
    end
    c = Class.new
    o.foo(c) { :foo }
    assert_equal(:foo, c.new.foo)

    o = Object.new
    o.instance_eval { define_singleton_method(:foo) { :foo } }
    assert_equal(:foo, o.foo)
  end

  def test_clone
    o = Object.new
    def o.foo; :foo; end
    m = o.method(:foo)
    def m.bar; :bar; end
    assert_equal(:foo, m.clone.call)
    assert_equal(:bar, m.clone.bar)
  end

  def test_call
    o = Object.new
    def o.foo; p 1; end
    def o.bar(x); x; end
    m = o.method(:foo)
    m.taint
    assert_raise(SecurityError) { m.call }
  end

  def test_inspect
    o = Object.new
    def o.foo; end
    m = o.method(:foo)
    assert_equal("#<Method: #{ o.inspect }.foo>", m.inspect)
    m = o.method(:foo)
    assert_equal("#<UnboundMethod: #{ class << o; self; end.inspect }#foo>", m.unbind.inspect)

    c = Class.new
    c.class_eval { def foo; end; }
    m = c.new.method(:foo)
    assert_equal("#<Method: #{ c.inspect }#foo>", m.inspect)
    m = c.instance_method(:foo)
    assert_equal("#<UnboundMethod: #{ c.inspect }#foo>", m.inspect)

    c2 = Class.new(c)
    c2.class_eval { private :foo }
    m2 = c2.new.method(:foo)
    assert_equal("#<Method: #{ c2.inspect }(#{ c.inspect })#foo>", m2.inspect)
  end

  def test_callee_top_level
    ruby do |w, r, e|
      w.puts "p __callee__"
      w.close
      assert_equal("nil", r.read.chomp)
      assert_match("", e.read.chomp)
    end
  end

  def test_caller_negative_level
    assert_raise(ArgumentError) { caller(-1) }
  end

  def test_attrset_ivar
    c = Class.new
    c.class_eval { attr_accessor :foo }
    o = c.new
    o.method(:foo=).call(42)
    assert_equal(42, o.foo)
    assert_raise(ArgumentError) { o.method(:foo=).call(1, 2, 3) }
    assert_raise(ArgumentError) { o.method(:foo).call(1) }
  end
end
