# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'

class TestMethod < Test::Unit::TestCase
  def setup
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  def teardown
    $VERBOSE = @verbose
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
  def mo7(a, b = nil, *c, d, &e) end
  def mo8(a, b = nil, *, d, &e) end
  def ma1((a), &b) nil && a end
  def mk1(**) end
  def mk2(**o) nil && o end
  def mk3(a, **o) nil && o end
  def mk4(a = nil, **o) nil && o end
  def mk5(a, b = nil, **o) nil && o end
  def mk6(a, b = nil, c, **o) nil && o end
  def mk7(a, b = nil, *c, d, **o) nil && o end
  def mk8(a, b = nil, *c, d, e:, f: nil, **o) nil && o end
  def mnk(**nil) end
  def mf(...) end

  class Base
    def foo() :base end
  end
  class Derived < Base
    def foo() :derived end
  end
  class T
    def initialize; end
    def initialize_copy(*) super end
    def initialize_clone(*) super end
    def initialize_dup(*) super end
    def respond_to_missing?(*) super end
    def normal_method; end
  end
  module M
    def func; end
    module_function :func
    def meth; :meth end
  end

  def mv1() end
  def mv2() end
  private :mv2
  def mv3() end
  protected :mv3

  class Visibility
    def mv1() end
    def mv2() end
    private :mv2
    def mv3() end
    protected :mv3
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
    assert_equal(-1, method(:mk1).arity)
    assert_equal(-1, method(:mk2).arity)
    assert_equal(-2, method(:mk3).arity)
    assert_equal(-1, method(:mk4).arity)
    assert_equal(-2, method(:mk5).arity)
    assert_equal(-3, method(:mk6).arity)
    assert_equal(-3, method(:mk7).arity)
  end

  def test_arity_special
    assert_equal(-1, method(:__send__).arity)
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

    # cleanup
    Derived.class_eval do
      remove_method :foo
      def foo() :derived; end
    end
  end

  def test_callee
    assert_equal(:test_callee, __method__)
    assert_equal(:m, Class.new {def m; __method__; end}.new.m)
    assert_equal(:m, Class.new {def m; tap{return __method__}; end}.new.m)
    assert_equal(:m, Class.new {define_method(:m) {__method__}}.new.m)
    assert_equal(:m, Class.new {define_method(:m) {tap{return __method__}}}.new.m)
    assert_nil(eval("class TestCallee; __method__; end"))

    assert_equal(:test_callee, __callee__)
    [
      ["method",              Class.new {def m; __callee__; end},],
      ["block",               Class.new {def m; tap{return __callee__}; end},],
      ["define_method",       Class.new {define_method(:m) {__callee__}}],
      ["define_method block", Class.new {define_method(:m) {tap{return __callee__}}}],
    ].each do |mesg, c|
      c.class_eval {alias m2 m}
      o = c.new
      assert_equal(:m, o.m, mesg)
      assert_equal(:m2, o.m2, mesg)
    end
    assert_nil(eval("class TestCallee; __callee__; end"))
  end

  def test_orphan_callee
    c = Class.new{def foo; proc{__callee__}; end; alias alias_foo foo}
    assert_equal(:alias_foo, c.new.alias_foo.call, '[Bug #11046]')
  end

  def test_method_in_define_method_block
    bug4606 = '[ruby-core:35386]'
    c = Class.new do
      [:m1, :m2].each do |m|
        define_method(m) do
          __method__
        end
      end
    end
    assert_equal(:m1, c.new.m1, bug4606)
    assert_equal(:m2, c.new.m2, bug4606)
  end

  def test_method_in_block_in_define_method_block
    bug4606 = '[ruby-core:35386]'
    c = Class.new do
      [:m1, :m2].each do |m|
        define_method(m) do
          tap { return __method__ }
        end
      end
    end
    assert_equal(:m1, c.new.m1, bug4606)
    assert_equal(:m2, c.new.m2, bug4606)
  end

  def test_body
    o = Object.new
    def o.foo; end
    assert_nothing_raised { RubyVM::InstructionSequence.disasm(o.method(:foo)) }
    assert_nothing_raised { RubyVM::InstructionSequence.disasm("x".method(:upcase)) }
    assert_nothing_raised { RubyVM::InstructionSequence.disasm(method(:to_s).to_proc) }
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
    assert_equal(Array.instance_method(:map).hash, Array.instance_method(:collect).hash)
    assert_kind_of(String, o.method(:foo).hash.to_s)
  end

  def test_owner
    c = Class.new do
      def foo; end
    end
    assert_equal(c, c.instance_method(:foo).owner)
    c2 = Class.new(c)
    assert_equal(c, c2.instance_method(:foo).owner)
  end

  def test_owner_missing
    c = Class.new do
      def respond_to_missing?(name, bool)
        name == :foo
      end
    end
    c2 = Class.new(c)
    assert_equal(c, c.new.method(:foo).owner)
    assert_equal(c2, c2.new.method(:foo).owner)
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
    class << o
      alias bar foo
    end
    m = o.method(:bar)
    assert_equal(:bar, m.name)
    assert_equal(:foo, m.original_name)
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

    cx = EnvUtil.labeled_class("X\u{1f431}")
    assert_raise_with_message(TypeError, /X\u{1f431}/) do
      o.method(cx)
    end
  end

  def test_bind_module_instance_method
    feature4254 = '[ruby-core:34267]'
    m = M.instance_method(:meth)
    assert_equal(:meth, m.bind(Object.new).call, feature4254)
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
    cx = EnvUtil.labeled_class("X\u{1f431}")
    assert_raise_with_message(TypeError, /X\u{1F431}/) do
      Class.new {define_method(cx) {}}
    end
  end

  def test_define_method_no_proc
    o = Object.new
    def o.foo(c)
      c.class_eval { define_method(:foo) }
    end
    c = Class.new
    assert_raise(ArgumentError) {o.foo(c)}

    bug11283 = '[ruby-core:69655] [Bug #11283]'
    assert_raise(ArgumentError, bug11283) {o.foo(c) {:foo}}
  end

  def test_define_singleton_method
    o = Object.new
    o.instance_eval { define_singleton_method(:foo) { :foo } }
    assert_equal(:foo, o.foo)
  end

  def test_define_singleton_method_no_proc
    o = Object.new
    assert_raise(ArgumentError) {
      o.instance_eval { define_singleton_method(:bar) }
    }

    bug11283 = '[ruby-core:69655] [Bug #11283]'
    def o.define(n)
      define_singleton_method(n)
    end
    assert_raise(ArgumentError, bug11283) {o.define(:bar) {:bar}}
  end

  def test_define_method_invalid_arg
    assert_raise(TypeError) do
      Class.new.class_eval { define_method(:foo, Object.new) }
    end

    assert_raise(TypeError) do
      Module.new.module_eval {define_method(:foo, Base.instance_method(:foo))}
    end
  end

  def test_define_singleton_method_with_extended_method
    bug8686 = "[ruby-core:56174]"

    m = Module.new do
      extend self

      def a
        "a"
      end
    end

    assert_nothing_raised(bug8686) do
      m.define_singleton_method(:a, m.method(:a))
    end
  end

  def test_define_method_transplating
    feature4254 = '[ruby-core:34267]'
    m = Module.new {define_method(:meth, M.instance_method(:meth))}
    assert_equal(:meth, Object.new.extend(m).meth, feature4254)
    c = Class.new {define_method(:meth, M.instance_method(:meth))}
    assert_equal(:meth, c.new.meth, feature4254)
  end

  def test_define_method_visibility
    c = Class.new do
      public
      define_method(:foo) {:foo}
      protected
      define_method(:bar) {:bar}
      private
      define_method(:baz) {:baz}
    end

    assert_equal(true, c.public_method_defined?(:foo))
    assert_equal(false, c.public_method_defined?(:bar))
    assert_equal(false, c.public_method_defined?(:baz))

    assert_equal(false, c.protected_method_defined?(:foo))
    assert_equal(true, c.protected_method_defined?(:bar))
    assert_equal(false, c.protected_method_defined?(:baz))

    assert_equal(false, c.private_method_defined?(:foo))
    assert_equal(false, c.private_method_defined?(:bar))
    assert_equal(true, c.private_method_defined?(:baz))

    m = Module.new do
      module_function
      define_method(:foo) {:foo}
    end
    assert_equal(true, m.respond_to?(:foo))
    assert_equal(false, m.public_method_defined?(:foo))
    assert_equal(false, m.protected_method_defined?(:foo))
    assert_equal(true, m.private_method_defined?(:foo))
  end

  def test_define_method_in_private_scope
    bug9005 = '[ruby-core:57747] [Bug #9005]'
    c = Class.new
    class << c
      public :define_method
    end
    TOPLEVEL_BINDING.eval("proc{|c|c.define_method(:x) {|x|throw x}}").call(c)
    o = c.new
    assert_throw(bug9005) {o.x(bug9005)}
  end

  def test_singleton_define_method_in_private_scope
    bug9141 = '[ruby-core:58497] [Bug #9141]'
    o = Object.new
    class << o
      public :define_singleton_method
    end
    TOPLEVEL_BINDING.eval("proc{|o|o.define_singleton_method(:x) {|x|throw x}}").call(o)
    assert_throw(bug9141) do
      o.x(bug9141)
    end
  end

  def test_super_in_proc_from_define_method
    c1 = Class.new {
      def m
        :m1
      end
    }
    c2 = Class.new(c1) { define_method(:m) { Proc.new { super() } } }
    assert_equal(:m1, c2.new.m.call, 'see [Bug #4881] and [Bug #3136]')
  end

  def test_clone
    o = Object.new
    def o.foo; :foo; end
    m = o.method(:foo)
    def m.bar; :bar; end
    assert_equal(:foo, m.clone.call)
    assert_equal(:bar, m.clone.bar)
  end

  def test_inspect
    o = Object.new
    def o.foo; end; line_no = __LINE__
    m = o.method(:foo)
    assert_equal("#<Method: #{ o.inspect }.foo() #{__FILE__}:#{line_no}>", m.inspect)
    m = o.method(:foo)
    assert_match("#<UnboundMethod: #{ class << o; self; end.inspect }#foo() #{__FILE__}:#{line_no}", m.unbind.inspect)

    c = Class.new
    c.class_eval { def foo; end; }; line_no = __LINE__
    m = c.new.method(:foo)
    assert_equal("#<Method: #{ c.inspect }#foo() #{__FILE__}:#{line_no}>", m.inspect)
    m = c.instance_method(:foo)
    assert_equal("#<UnboundMethod: #{ c.inspect }#foo() #{__FILE__}:#{line_no}>", m.inspect)

    c2 = Class.new(c)
    c2.class_eval { private :foo }
    m2 = c2.new.method(:foo)
    assert_equal("#<Method: #{ c2.inspect }(#{ c.inspect })#foo() #{__FILE__}:#{line_no}>", m2.inspect)

    bug7806 = '[ruby-core:52048] [Bug #7806]'
    c3 = Class.new(c)
    c3.class_eval { alias bar foo }
    m3 = c3.new.method(:bar)
    assert_equal("#<Method: #{c3.inspect}(#{c.inspect})#bar(foo)() #{__FILE__}:#{line_no}>", m3.inspect, bug7806)

    bug15608 = '[ruby-core:91570] [Bug #15608]'
    c4 = Class.new(c)
    c4.class_eval { alias bar foo }
    o = c4.new
    o.singleton_class
    m4 = o.method(:bar)
    assert_equal("#<Method: #{c4.inspect}(#{c.inspect})#bar(foo)() #{__FILE__}:#{line_no}>", m4.inspect, bug15608)
  end

  def test_callee_top_level
    assert_in_out_err([], "p __callee__", %w(nil), [])
  end

  def test_caller_top_level
    assert_in_out_err([], "p caller", %w([]), [])
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

  def test_default_accessibility
    tmethods = T.public_instance_methods
    assert_include tmethods, :normal_method, 'normal methods are public by default'
    assert_not_include tmethods, :initialize, '#initialize is private'
    assert_not_include tmethods, :initialize_copy, '#initialize_copy is private'
    assert_not_include tmethods, :initialize_clone, '#initialize_clone is private'
    assert_not_include tmethods, :initialize_dup, '#initialize_dup is private'
    assert_not_include tmethods, :respond_to_missing?, '#respond_to_missing? is private'
    mmethods = M.public_instance_methods
    assert_not_include mmethods, :func, 'module methods are private by default'
    assert_include mmethods, :meth, 'normal methods are public by default'
  end

  def test_respond_to_missing_argument
    obj = Struct.new(:mid).new
    def obj.respond_to_missing?(id, *)
      self.mid = id
      true
    end
    assert_kind_of(Method, obj.method("bug15640"))
    assert_kind_of(Symbol, obj.mid)
    assert_equal("bug15640", obj.mid.to_s)

    arg = Struct.new(:to_str).new("bug15640_2")
    assert_kind_of(Method, obj.method(arg))
    assert_kind_of(Symbol, obj.mid)
    assert_equal("bug15640_2", obj.mid.to_s)
  end

  define_method(:pm0) {||}
  define_method(:pm1) {|a|}
  define_method(:pm2) {|a, b|}
  define_method(:pmo1) {|a = nil, &b|}
  define_method(:pmo2) {|a, b = nil|}
  define_method(:pmo3) {|*a|}
  define_method(:pmo4) {|a, *b, &c|}
  define_method(:pmo5) {|a, *b, c|}
  define_method(:pmo6) {|a, *b, c, &d|}
  define_method(:pmo7) {|a, b = nil, *c, d, &e|}
  define_method(:pma1) {|(a), &b| nil && a}
  define_method(:pmk1) {|**|}
  define_method(:pmk2) {|**o|}
  define_method(:pmk3) {|a, **o|}
  define_method(:pmk4) {|a = nil, **o|}
  define_method(:pmk5) {|a, b = nil, **o|}
  define_method(:pmk6) {|a, b = nil, c, **o|}
  define_method(:pmk7) {|a, b = nil, *c, d, **o|}
  define_method(:pmk8) {|a, b = nil, *c, d, e:, f: nil, **o|}
  define_method(:pmnk) {|**nil|}

  def test_bound_parameters
    assert_equal([], method(:m0).parameters)
    assert_equal([[:req, :a]], method(:m1).parameters)
    assert_equal([[:req, :a], [:req, :b]], method(:m2).parameters)
    assert_equal([[:opt, :a], [:block, :b]], method(:mo1).parameters)
    assert_equal([[:req, :a], [:opt, :b]], method(:mo2).parameters)
    assert_equal([[:rest, :a]], method(:mo3).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:block, :c]], method(:mo4).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c]], method(:mo5).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c], [:block, :d]], method(:mo6).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:block, :e]], method(:mo7).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest], [:req, :d], [:block, :e]], method(:mo8).parameters)
    assert_equal([[:req], [:block, :b]], method(:ma1).parameters)
    assert_equal([[:keyrest]], method(:mk1).parameters)
    assert_equal([[:keyrest, :o]], method(:mk2).parameters)
    assert_equal([[:req, :a], [:keyrest, :o]], method(:mk3).parameters)
    assert_equal([[:opt, :a], [:keyrest, :o]], method(:mk4).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:keyrest, :o]], method(:mk5).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:req, :c], [:keyrest, :o]], method(:mk6).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:keyrest, :o]], method(:mk7).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:keyreq, :e], [:key, :f], [:keyrest, :o]], method(:mk8).parameters)
    assert_equal([[:nokey]], method(:mnk).parameters)
    # pending
    assert_equal([[:rest, :*], [:block, :&]], method(:mf).parameters)
  end

  def test_unbound_parameters
    assert_equal([], self.class.instance_method(:m0).parameters)
    assert_equal([[:req, :a]], self.class.instance_method(:m1).parameters)
    assert_equal([[:req, :a], [:req, :b]], self.class.instance_method(:m2).parameters)
    assert_equal([[:opt, :a], [:block, :b]], self.class.instance_method(:mo1).parameters)
    assert_equal([[:req, :a], [:opt, :b]], self.class.instance_method(:mo2).parameters)
    assert_equal([[:rest, :a]], self.class.instance_method(:mo3).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:block, :c]], self.class.instance_method(:mo4).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c]], self.class.instance_method(:mo5).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c], [:block, :d]], self.class.instance_method(:mo6).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:block, :e]], self.class.instance_method(:mo7).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest], [:req, :d], [:block, :e]], self.class.instance_method(:mo8).parameters)
    assert_equal([[:req], [:block, :b]], self.class.instance_method(:ma1).parameters)
    assert_equal([[:keyrest]], self.class.instance_method(:mk1).parameters)
    assert_equal([[:keyrest, :o]], self.class.instance_method(:mk2).parameters)
    assert_equal([[:req, :a], [:keyrest, :o]], self.class.instance_method(:mk3).parameters)
    assert_equal([[:opt, :a], [:keyrest, :o]], self.class.instance_method(:mk4).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:keyrest, :o]], self.class.instance_method(:mk5).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:req, :c], [:keyrest, :o]], self.class.instance_method(:mk6).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:keyrest, :o]], self.class.instance_method(:mk7).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:keyreq, :e], [:key, :f], [:keyrest, :o]], self.class.instance_method(:mk8).parameters)
    assert_equal([[:nokey]], self.class.instance_method(:mnk).parameters)
    # pending
    assert_equal([[:rest, :*], [:block, :&]], self.class.instance_method(:mf).parameters)
  end

  def test_bmethod_bound_parameters
    assert_equal([], method(:pm0).parameters)
    assert_equal([[:req, :a]], method(:pm1).parameters)
    assert_equal([[:req, :a], [:req, :b]], method(:pm2).parameters)
    assert_equal([[:opt, :a], [:block, :b]], method(:pmo1).parameters)
    assert_equal([[:req, :a], [:opt, :b]], method(:pmo2).parameters)
    assert_equal([[:rest, :a]], method(:pmo3).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:block, :c]], method(:pmo4).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c]], method(:pmo5).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c], [:block, :d]], method(:pmo6).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:block, :e]], method(:pmo7).parameters)
    assert_equal([[:req], [:block, :b]], method(:pma1).parameters)
    assert_equal([[:keyrest]], method(:pmk1).parameters)
    assert_equal([[:keyrest, :o]], method(:pmk2).parameters)
    assert_equal([[:req, :a], [:keyrest, :o]], method(:pmk3).parameters)
    assert_equal([[:opt, :a], [:keyrest, :o]], method(:pmk4).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:keyrest, :o]], method(:pmk5).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:req, :c], [:keyrest, :o]], method(:pmk6).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:keyrest, :o]], method(:pmk7).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:keyreq, :e], [:key, :f], [:keyrest, :o]], method(:pmk8).parameters)
    assert_equal([[:nokey]], method(:pmnk).parameters)
  end

  def test_bmethod_unbound_parameters
    assert_equal([], self.class.instance_method(:pm0).parameters)
    assert_equal([[:req, :a]], self.class.instance_method(:pm1).parameters)
    assert_equal([[:req, :a], [:req, :b]], self.class.instance_method(:pm2).parameters)
    assert_equal([[:opt, :a], [:block, :b]], self.class.instance_method(:pmo1).parameters)
    assert_equal([[:req, :a], [:opt, :b]], self.class.instance_method(:pmo2).parameters)
    assert_equal([[:rest, :a]], self.class.instance_method(:pmo3).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:block, :c]], self.class.instance_method(:pmo4).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c]], self.class.instance_method(:pmo5).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c], [:block, :d]], self.class.instance_method(:pmo6).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:block, :e]], self.class.instance_method(:pmo7).parameters)
    assert_equal([[:req], [:block, :b]], self.class.instance_method(:pma1).parameters)
    assert_equal([[:req], [:block, :b]], self.class.instance_method(:pma1).parameters)
    assert_equal([[:keyrest]], self.class.instance_method(:pmk1).parameters)
    assert_equal([[:keyrest, :o]], self.class.instance_method(:pmk2).parameters)
    assert_equal([[:req, :a], [:keyrest, :o]], self.class.instance_method(:pmk3).parameters)
    assert_equal([[:opt, :a], [:keyrest, :o]], self.class.instance_method(:pmk4).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:keyrest, :o]], self.class.instance_method(:pmk5).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:req, :c], [:keyrest, :o]], self.class.instance_method(:pmk6).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:keyrest, :o]], self.class.instance_method(:pmk7).parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:keyreq, :e], [:key, :f], [:keyrest, :o]], self.class.instance_method(:pmk8).parameters)
    assert_equal([[:nokey]], self.class.instance_method(:pmnk).parameters)
  end

  def test_hidden_parameters
    instance_eval("def m((_)"+",(_)"*256+");end")
    assert_empty(method(:m).parameters.map{|_,n|n}.compact)
  end

  def test_method_parameters_inspect
    assert_include(method(:m0).inspect, "()")
    assert_include(method(:m1).inspect, "(a)")
    assert_include(method(:m2).inspect, "(a, b)")
    assert_include(method(:mo1).inspect, "(a=..., &b)")
    assert_include(method(:mo2).inspect, "(a, b=...)")
    assert_include(method(:mo3).inspect, "(*a)")
    assert_include(method(:mo4).inspect, "(a, *b, &c)")
    assert_include(method(:mo5).inspect, "(a, *b, c)")
    assert_include(method(:mo6).inspect, "(a, *b, c, &d)")
    assert_include(method(:mo7).inspect, "(a, b=..., *c, d, &e)")
    assert_include(method(:mo8).inspect, "(a, b=..., *, d, &e)")
    assert_include(method(:ma1).inspect, "(_, &b)")
    assert_include(method(:mk1).inspect, "(**)")
    assert_include(method(:mk2).inspect, "(**o)")
    assert_include(method(:mk3).inspect, "(a, **o)")
    assert_include(method(:mk4).inspect, "(a=..., **o)")
    assert_include(method(:mk5).inspect, "(a, b=..., **o)")
    assert_include(method(:mk6).inspect, "(a, b=..., c, **o)")
    assert_include(method(:mk7).inspect, "(a, b=..., *c, d, **o)")
    assert_include(method(:mk8).inspect, "(a, b=..., *c, d, e:, f: ..., **o)")
    assert_include(method(:mnk).inspect, "(**nil)")
    assert_include(method(:mf).inspect, "(...)")
  end

  def test_unbound_method_parameters_inspect
    assert_include(self.class.instance_method(:m0).inspect, "()")
    assert_include(self.class.instance_method(:m1).inspect, "(a)")
    assert_include(self.class.instance_method(:m2).inspect, "(a, b)")
    assert_include(self.class.instance_method(:mo1).inspect, "(a=..., &b)")
    assert_include(self.class.instance_method(:mo2).inspect, "(a, b=...)")
    assert_include(self.class.instance_method(:mo3).inspect, "(*a)")
    assert_include(self.class.instance_method(:mo4).inspect, "(a, *b, &c)")
    assert_include(self.class.instance_method(:mo5).inspect, "(a, *b, c)")
    assert_include(self.class.instance_method(:mo6).inspect, "(a, *b, c, &d)")
    assert_include(self.class.instance_method(:mo7).inspect, "(a, b=..., *c, d, &e)")
    assert_include(self.class.instance_method(:mo8).inspect, "(a, b=..., *, d, &e)")
    assert_include(self.class.instance_method(:ma1).inspect, "(_, &b)")
    assert_include(self.class.instance_method(:mk1).inspect, "(**)")
    assert_include(self.class.instance_method(:mk2).inspect, "(**o)")
    assert_include(self.class.instance_method(:mk3).inspect, "(a, **o)")
    assert_include(self.class.instance_method(:mk4).inspect, "(a=..., **o)")
    assert_include(self.class.instance_method(:mk5).inspect, "(a, b=..., **o)")
    assert_include(self.class.instance_method(:mk6).inspect, "(a, b=..., c, **o)")
    assert_include(self.class.instance_method(:mk7).inspect, "(a, b=..., *c, d, **o)")
    assert_include(self.class.instance_method(:mk8).inspect, "(a, b=..., *c, d, e:, f: ..., **o)")
    assert_include(self.class.instance_method(:mnk).inspect, "(**nil)")
    assert_include(self.class.instance_method(:mf).inspect, "(...)")
  end

  def test_public_method_with_zsuper_method
    c = Class.new
    c.class_eval do
      def foo
        :ok
      end
      private :foo
    end
    d = Class.new(c)
    d.class_eval do
      public :foo
    end
    assert_equal(:ok, d.new.public_method(:foo).call)
  end

  def test_public_methods_with_extended
    m = Module.new do def m1; end end
    a = Class.new do def a; end end
    bug = '[ruby-dev:41553]'
    obj = a.new
    assert_equal([:a], obj.public_methods(false), bug)
    obj.extend(m)
    assert_equal([:m1, :a], obj.public_methods(false), bug)
  end

  def test_visibility
    assert_equal('method', defined?(mv1))
    assert_equal('method', defined?(mv2))
    assert_equal('method', defined?(mv3))

    assert_equal('method', defined?(self.mv1))
    assert_equal(nil,      defined?(self.mv2))
    assert_equal('method', defined?(self.mv3))

    assert_equal(true,  respond_to?(:mv1))
    assert_equal(false, respond_to?(:mv2))
    assert_equal(false, respond_to?(:mv3))

    assert_equal(true,  respond_to?(:mv1, true))
    assert_equal(true,  respond_to?(:mv2, true))
    assert_equal(true,  respond_to?(:mv3, true))

    assert_nothing_raised { mv1 }
    assert_nothing_raised { mv2 }
    assert_nothing_raised { mv3 }

    assert_nothing_raised { self.mv1 }
    assert_nothing_raised { self.mv2 }
    assert_raise(NoMethodError) { (self).mv2 }
    assert_nothing_raised { self.mv3 }

    v = Visibility.new

    assert_equal('method', defined?(v.mv1))
    assert_equal(nil,      defined?(v.mv2))
    assert_equal(nil,      defined?(v.mv3))

    assert_equal(true,  v.respond_to?(:mv1))
    assert_equal(false, v.respond_to?(:mv2))
    assert_equal(false, v.respond_to?(:mv3))

    assert_equal(true,  v.respond_to?(:mv1, true))
    assert_equal(true,  v.respond_to?(:mv2, true))
    assert_equal(true,  v.respond_to?(:mv3, true))

    assert_nothing_raised { v.mv1 }
    assert_raise(NoMethodError) { v.mv2 }
    assert_raise(NoMethodError) { v.mv3 }

    assert_nothing_raised { v.__send__(:mv1) }
    assert_nothing_raised { v.__send__(:mv2) }
    assert_nothing_raised { v.__send__(:mv3) }

    assert_nothing_raised { v.instance_eval { mv1 } }
    assert_nothing_raised { v.instance_eval { mv2 } }
    assert_nothing_raised { v.instance_eval { mv3 } }
  end

  def test_bound_method_entry
    bug6171 = '[ruby-core:43383]'
    assert_ruby_status([], <<-EOC, bug6171)
      class Bug6171
        def initialize(target)
          define_singleton_method(:reverse, target.method(:reverse).to_proc)
        end
      end
      100.times {p = Bug6171.new('test'); 1000.times {p.reverse}}
      EOC
  end

  def test_unbound_method_proc_coerce
    # '&' coercion of an UnboundMethod raises TypeError
    assert_raise(TypeError) do
      Class.new do
        define_method('foo', &Object.instance_method(:to_s))
      end
    end
  end

  def test___dir__
    assert_instance_of String, __dir__
    assert_equal(File.dirname(File.realpath(__FILE__)), __dir__)
    bug8436 = '[ruby-core:55123] [Bug #8436]'
    file, line = *binding.source_location
    file = File.realpath(file)
    assert_equal(__dir__, eval("__dir__", binding, file, line), bug8436)
    bug8662 = '[ruby-core:56099] [Bug #8662]'
    assert_equal("arbitrary", eval("__dir__", binding, "arbitrary/file.rb"), bug8662)
    assert_equal("arbitrary", Object.new.instance_eval("__dir__", "arbitrary/file.rb"), bug8662)
  end

  def test_alias_owner
    bug7613 = '[ruby-core:51105]'
    bug7993 = '[Bug #7993]'
    c = Class.new {
      def foo
      end
      prepend Module.new
      attr_reader :zot
    }
    x = c.new
    class << x
      alias bar foo
    end
    assert_equal(c, c.instance_method(:foo).owner)
    assert_equal(c, x.method(:foo).owner)
    assert_equal(x.singleton_class, x.method(:bar).owner)
    assert_equal(x.method(:foo), x.method(:bar), bug7613)
    assert_equal(c, x.method(:zot).owner, bug7993)
    assert_equal(c, c.instance_method(:zot).owner, bug7993)
  end

  def test_included
    m = Module.new {
      def foo
      end
    }
    c = Class.new {
      def foo
      end
      include m
    }
    assert_equal(c, c.instance_method(:foo).owner)
  end

  def test_prepended
    bug7836 = '[ruby-core:52160] [Bug #7836]'
    bug7988 = '[ruby-core:53038] [Bug #7988]'
    m = Module.new {
      def foo
      end
    }
    c = Class.new {
      def foo
      end
      prepend m
    }
    assert_raise(NameError, bug7988) {Module.new{prepend m}.instance_method(:bar)}
    true || c || bug7836
  end

  def test_gced_bmethod
    assert_normal_exit %q{
      require 'irb'
      IRB::Irb.module_eval do
        define_method(:eval_input) do
          IRB::Irb.module_eval { alias_method :eval_input, :to_s }
          GC.start
          Kernel
        end
      end
      IRB.start
    }, '[Bug #7825]'
  end

  def test_singleton_method
    feature8391 = '[ruby-core:54914] [Feature #8391]'
    c1 = Class.new
    c1.class_eval { def foo; :foo; end }
    o = c1.new
    def o.bar; :bar; end
    assert_nothing_raised(NameError) {o.method(:foo)}
    assert_raise(NameError, feature8391) {o.singleton_method(:foo)}
    m = assert_nothing_raised(NameError, feature8391) {break o.singleton_method(:bar)}
    assert_equal(:bar, m.call, feature8391)
  end

  def test_singleton_method_prepend
    bug14658 = '[Bug #14658]'
    c1 = Class.new
    o = c1.new
    def o.bar; :bar; end
    class << o; prepend Module.new; end
    m = assert_nothing_raised(NameError, bug14658) {o.singleton_method(:bar)}
    assert_equal(:bar, m.call, bug14658)

    o = Object.new
    assert_raise(NameError, bug14658) {o.singleton_method(:bar)}
  end

  Feature9783 = '[ruby-core:62212] [Feature #9783]'

  def assert_curry_three_args(m)
    curried = m.curry
    assert_equal(6, curried.(1).(2).(3), Feature9783)

    curried = m.curry(3)
    assert_equal(6, curried.(1).(2).(3), Feature9783)

    assert_raise_with_message(ArgumentError, /wrong number/) {m.curry(2)}
  end

  def test_curry_method
    c = Class.new {
      def three_args(a,b,c) a + b + c end
    }
    assert_curry_three_args(c.new.method(:three_args))
  end

  def test_curry_from_proc
    c = Class.new {
      define_method(:three_args) {|x,y,z| x + y + z}
    }
    assert_curry_three_args(c.new.method(:three_args))
  end

  def assert_curry_var_args(m)
    curried = m.curry(3)
    assert_equal([1, 2, 3], curried.(1).(2).(3), Feature9783)

    curried = m.curry(2)
    assert_equal([1, 2], curried.(1).(2), Feature9783)

    curried = m.curry(0)
    assert_equal([1], curried.(1), Feature9783)
  end

  def test_curry_var_args
    c = Class.new {
      def var_args(*args) args end
    }
    assert_curry_var_args(c.new.method(:var_args))
  end

  def test_curry_from_proc_var_args
    c = Class.new {
      define_method(:var_args) {|*args| args}
    }
    assert_curry_var_args(c.new.method(:var_args))
  end

  Feature9781 = '[ruby-core:62202] [Feature #9781]'

  def test_super_method
    o = Derived.new
    m = o.method(:foo).super_method
    assert_equal(Base, m.owner, Feature9781)
    assert_same(o, m.receiver, Feature9781)
    assert_equal(:foo, m.name, Feature9781)
    m = assert_nothing_raised(NameError, Feature9781) {break m.super_method}
    assert_nil(m, Feature9781)
  end

  def test_super_method_unbound
    m = Derived.instance_method(:foo)
    m = m.super_method
    assert_equal(Base.instance_method(:foo), m, Feature9781)
    m = assert_nothing_raised(NameError, Feature9781) {break m.super_method}
    assert_nil(m, Feature9781)

    bug11419 = '[ruby-core:70254]'
    m = Object.instance_method(:tap)
    m = assert_nothing_raised(NameError, bug11419) {break m.super_method}
    assert_nil(m, bug11419)
  end

  def test_super_method_module
    m1 = Module.new {def foo; end}
    c1 = Class.new(Derived) {include m1; def foo; end}
    m = c1.instance_method(:foo)
    assert_equal(c1, m.owner, Feature9781)
    m = m.super_method
    assert_equal(m1, m.owner, Feature9781)
    m = m.super_method
    assert_equal(Derived, m.owner, Feature9781)
    m = m.super_method
    assert_equal(Base, m.owner, Feature9781)
    m2 = Module.new {def foo; end}
    o = c1.new.extend(m2)
    m = o.method(:foo)
    assert_equal(m2, m.owner, Feature9781)
    m = m.super_method
    assert_equal(c1, m.owner, Feature9781)
    assert_same(o, m.receiver, Feature9781)

    c1 = Class.new {def foo; end}
    c2 = Class.new(c1) {include m1; include m2}
    m = c2.instance_method(:foo)
    assert_equal(m2, m.owner)
    m = m.super_method
    assert_equal(m1, m.owner)
    m = m.super_method
    assert_equal(c1, m.owner)
    assert_nil(m.super_method)
  end

  def test_super_method_bind_unbind_clone
    bug15629_m1 = Module.new do
      def foo; end
    end

    bug15629_m2 = Module.new do
      def foo; end
    end

    bug15629_c = Class.new do
      include bug15629_m1
      include bug15629_m2
    end

    o  = bug15629_c.new
    m = o.method(:foo)
    sm = m.super_method
    im = bug15629_c.instance_method(:foo)
    sim = im.super_method

    assert_equal(sm, m.clone.super_method)
    assert_equal(sim, m.unbind.super_method)
    assert_equal(sim, m.unbind.clone.super_method)
    assert_equal(sim, im.clone.super_method)
    assert_equal(sm, m.unbind.bind(o).super_method)
    assert_equal(sm, m.unbind.clone.bind(o).super_method)
    assert_equal(sm, im.bind(o).super_method)
    assert_equal(sm, im.clone.bind(o).super_method)
  end

  def test_super_method_removed
    c1 = Class.new {private def foo; end}
    c2 = Class.new(c1) {public :foo}
    c3 = Class.new(c2) {def foo; end}
    c1.class_eval {undef foo}
    m = c3.instance_method(:foo)
    m = assert_nothing_raised(NameError, Feature9781) {break m.super_method}
    assert_nil(m, Feature9781)
  end

  def test_prepended_public_zsuper
    mod = EnvUtil.labeled_module("Mod") {private def foo; :ok end}
    mods = [mod]
    obj = Object.new.extend(mod)
    class << obj
      public :foo
    end
    2.times do |i|
      mods.unshift(mod = EnvUtil.labeled_module("Mod#{i}") {def foo; end})
      obj.singleton_class.prepend(mod)
    end
    m = obj.method(:foo)
    assert_equal(mods, mods.map {m.owner.tap {m = m.super_method}})
    assert_nil(m)
  end

  def test_super_method_with_prepended_module
    bug = '[ruby-core:81666] [Bug #13656] should be the method of the parent'
    c1 = EnvUtil.labeled_class("C1") {def m; end}
    c2 = EnvUtil.labeled_class("C2", c1) {def m; end}
    c2.prepend(EnvUtil.labeled_module("M"))
    m1 = c1.instance_method(:m)
    m2 = c2.instance_method(:m).super_method
    assert_equal(m1, m2, bug)
    assert_equal(c1, m2.owner, bug)
    assert_equal(m1.source_location, m2.source_location, bug)
  end

  def test_super_method_after_bind
    assert_nil String.instance_method(:length).bind(String.new).super_method,
      '[ruby-core:85231] [Bug #14421]'
  end

  def test_super_method_alias
    c0 = Class.new do
      def m1
        [:C0_m1]
      end
      def m2
        [:C0_m2]
      end
    end

    c1 = Class.new(c0) do
      def m1
        [:C1_m1] + super
      end
      alias m2 m1
    end

    c2 = Class.new(c1) do
      def m2
        [:C2_m2] + super
      end
    end
    o1 = c2.new
    assert_equal([:C2_m2, :C1_m1, :C0_m1], o1.m2)

    m = o1.method(:m2)
    assert_equal([:C2_m2, :C1_m1, :C0_m1], m.call)

    m = m.super_method
    assert_equal([:C1_m1, :C0_m1], m.call)

    m = m.super_method
    assert_equal([:C0_m1], m.call)

    assert_nil(m.super_method)
  end

  def test_super_method_alias_to_prepended_module
    m = Module.new do
      def m1
        [:P_m1] + super
      end

      def m2
        [:P_m2] + super
      end
    end

    c0 = Class.new do
      def m1
        [:C0_m1]
      end
    end

    c1 = Class.new(c0) do
      def m1
        [:C1_m1] + super
      end
      prepend m
      alias m2 m1
    end

    o1 = c1.new
    assert_equal([:P_m2, :P_m1, :C1_m1, :C0_m1], o1.m2)

    m = o1.method(:m2)
    assert_equal([:P_m2, :P_m1, :C1_m1, :C0_m1], m.call)

    m = m.super_method
    assert_equal([:P_m1, :C1_m1, :C0_m1], m.call)

    m = m.super_method
    assert_equal([:C1_m1, :C0_m1], m.call)

    m = m.super_method
    assert_equal([:C0_m1], m.call)

    assert_nil(m.super_method)
  end

  def rest_parameter(*rest)
    rest
  end

  def test_splat_long_array
    if File.exist?('/etc/os-release') && File.read('/etc/os-release').include?('openSUSE Leap')
      # For RubyCI's openSUSE machine http://rubyci.s3.amazonaws.com/opensuseleap/ruby-trunk/recent.html, which tends to die with NoMemoryError here.
      skip 'do not exhaust memory on RubyCI openSUSE Leap machine'
    end
    n = 10_000_000
    assert_equal n  , rest_parameter(*(1..n)).size, '[Feature #10440]'
  end

  class C
    D = "Const_D"
    def foo
      a = b = c = a = b = c = 12345
    end
  end

  def test_to_proc_binding
    bug11012 = '[ruby-core:68673] [Bug #11012]'

    b = C.new.method(:foo).to_proc.binding
    assert_equal([], b.local_variables, bug11012)
    assert_equal("Const_D", b.eval("D"), bug11012) # Check CREF

    assert_raise(NameError, bug11012){ b.local_variable_get(:foo) }
    assert_equal(123, b.local_variable_set(:foo, 123), bug11012)
    assert_equal(123, b.local_variable_get(:foo), bug11012)
    assert_equal(456, b.local_variable_set(:bar, 456), bug11012)
    assert_equal(123, b.local_variable_get(:foo), bug11012)
    assert_equal(456, b.local_variable_get(:bar), bug11012)
    assert_equal([:bar, :foo], b.local_variables.sort, bug11012)
  end

  MethodInMethodClass_Setup = -> do
    remove_const :MethodInMethodClass if defined? MethodInMethodClass

    class MethodInMethodClass
      def m1
        def m2
        end
        self.class.send(:define_method, :m3){} # [Bug #11754]
      end
      private
    end
  end

  def test_method_in_method_visibility_should_be_public
    MethodInMethodClass_Setup.call

    assert_equal([:m1].sort, MethodInMethodClass.public_instance_methods(false).sort)
    assert_equal([].sort, MethodInMethodClass.private_instance_methods(false).sort)

    MethodInMethodClass.new.m1
    assert_equal([:m1, :m2, :m3].sort, MethodInMethodClass.public_instance_methods(false).sort)
    assert_equal([].sort, MethodInMethodClass.private_instance_methods(false).sort)
  end

  def test_define_method_with_symbol
    assert_normal_exit %q{
      define_method(:foo, &:to_s)
      define_method(:bar, :to_s.to_proc)
    }, '[Bug #11850]'
    c = Class.new{
      define_method(:foo, &:to_s)
      define_method(:bar, :to_s.to_proc)
    }
    obj = c.new
    assert_equal('1', obj.foo(1))
    assert_equal('1', obj.bar(1))
  end

  def test_argument_error_location
    body = <<-'END_OF_BODY'
    eval <<-'EOS'
    $line_lambda = __LINE__; $f = lambda do
      _x = 1
    end
    $line_method = __LINE__; def foo
      _x = 1
    end
    begin
      $f.call(1)
    rescue ArgumentError => e
      assert_equal "(eval):#{$line_lambda.to_s}:in `block in <main>'", e.backtrace.first
    end
    begin
      foo(1)
    rescue ArgumentError => e
      assert_equal "(eval):#{$line_method}:in `foo'", e.backtrace.first
    end
    EOS
    END_OF_BODY

    assert_separately [], body
    # without trace insn
    assert_separately [], "RubyVM::InstructionSequence.compile_option = {trace_instruction: false}\n" + body
  end

  def test_zsuper_private_override_instance_method
    assert_separately(%w(--disable-gems), <<-'end;', timeout: 30)
      # Bug #16942 [ruby-core:98691]
      module M
        def x
        end
      end

      module M2
        prepend Module.new
        include M
        private :x
      end

      ::Object.prepend(M2)

      m = Object.instance_method(:x)
      assert_equal M, m.owner
    end;
  end

  def test_eqq
    assert_operator(0.method(:<), :===, 5)
    assert_not_operator(0.method(:<), :===, -5)
  end

  def test_compose_with_method
    c = Class.new {
      def f(x) x * 2 end
      def g(x) x + 1 end
    }
    f = c.new.method(:f)
    g = c.new.method(:g)

    assert_equal(6, (f << g).call(2))
    assert_equal(6, (g >> f).call(2))
  end

  def test_compose_with_proc
    c = Class.new {
      def f(x) x * 2 end
    }
    f = c.new.method(:f)
    g = proc {|x| x + 1}

    assert_equal(6, (f << g).call(2))
    assert_equal(6, (g >> f).call(2))
  end

  def test_compose_with_callable
    c = Class.new {
      def f(x) x * 2 end
    }
    c2 = Class.new {
      def call(x) x + 1 end
    }
    f = c.new.method(:f)
    g = c2.new

    assert_equal(6, (f << g).call(2))
    assert_equal(5, (f >> g).call(2))
  end

  def test_compose_with_noncallable
    c = Class.new {
      def f(x) x * 2 end
    }
    f = c.new.method(:f)

    assert_raise(TypeError) {
      f << 5
    }
    assert_raise(TypeError) {
      f >> 5
    }
  end

  def test_umethod_bind_call
    foo = Base.instance_method(:foo)
    assert_equal(:base, foo.bind_call(Base.new))
    assert_equal(:base, foo.bind_call(Derived.new))

    plus = Integer.instance_method(:+)
    assert_equal(3, plus.bind_call(1, 2))
  end

  def test_method_list
    # chkbuild lists all methods.
    # The following code emulate this listing.

    # use_symbol = Object.instance_methods[0].is_a?(Symbol)
    nummodule = nummethod = 0
    mods = []
    ObjectSpace.each_object(Module) {|m| mods << m if m.name }
    mods = mods.sort_by {|m| m.name }
    mods.each {|mod|
      nummodule += 1
      mc = mod.kind_of?(Class) ? "class" : "module"
      puts_line = "#{mc} #{mod.name} #{(mod.ancestors - [mod]).inspect}"
      puts_line = puts_line # prevent unused var warning
      mod.singleton_methods(false).sort.each {|methname|
        nummethod += 1
        meth = mod.method(methname)
        line = "#{mod.name}.#{methname} #{meth.arity}"
        line << " not-implemented" if !mod.respond_to?(methname)
        # puts line
      }
      ms = mod.instance_methods(false)
      if true or use_symbol
        ms << :initialize if mod.private_instance_methods(false).include? :initialize
      else
        ms << "initialize" if mod.private_instance_methods(false).include? "initialize"
      end

      ms.sort.each {|methname|
        nummethod += 1
        meth = mod.instance_method(methname)
        line = "#{mod.name}\##{methname} #{meth.arity}"
        line << " not-implemented" if /\(not-implemented\)/ =~ meth.inspect
        # puts line
      }
    }
    # puts "#{nummodule} modules, #{nummethod} methods"

    assert_operator nummodule, :>, 0
    assert_operator nummethod, :>, 0
  end

  def test_invalidating_CC_ASAN
    assert_ruby_status('using Module.new')
  end
end
