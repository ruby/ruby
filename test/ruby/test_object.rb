# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'

class TestObject < Test::Unit::TestCase
  def setup
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  def teardown
    $VERBOSE = @verbose
  end

  def test_itself
    feature6373 = '[ruby-core:44704] [Feature #6373]'
    object = Object.new
    assert_same(object, object.itself, feature6373)
  end

  def test_yield_self
    feature = '[ruby-core:46320] [Feature #6721]'
    object = Object.new
    assert_same(self, object.yield_self {self}, feature)
    assert_same(object, object.yield_self {|x| break x}, feature)
    enum = object.yield_self
    assert_instance_of(Enumerator, enum)
    assert_equal(1, enum.size)
  end

  def test_dup
    assert_equal 1, 1.dup
    assert_equal true, true.dup
    assert_equal nil, nil.dup
    assert_equal false, false.dup
    x = :x; assert_equal x, x.dup
    x = "bug13145".intern; assert_equal x, x.dup
    x = 1 << 64; assert_equal x, x.dup
    x = 1.72723e-77; assert_equal x, x.dup

    assert_raise(TypeError) do
      Object.new.instance_eval { initialize_copy(1) }
    end
  end

  def test_clone
    a = Object.new
    def a.b; 2 end

    a.freeze
    c = a.clone
    assert_equal(true, c.frozen?)
    assert_equal(2, c.b)

    assert_raise(ArgumentError) {a.clone(freeze: [])}
    d = a.clone(freeze: false)
    def d.e; 3; end
    assert_equal(false, d.frozen?)
    assert_equal(2, d.b)
    assert_equal(3, d.e)

    assert_equal 1, 1.clone
    assert_equal true, true.clone
    assert_equal nil, nil.clone
    assert_equal false, false.clone
    x = :x; assert_equal x, x.dup
    x = "bug13145".intern; assert_equal x, x.dup
    x = 1 << 64; assert_equal x, x.clone
    x = 1.72723e-77; assert_equal x, x.clone
    assert_raise(ArgumentError) {1.clone(freeze: false)}
    assert_raise(ArgumentError) {true.clone(freeze: false)}
    assert_raise(ArgumentError) {nil.clone(freeze: false)}
    assert_raise(ArgumentError) {false.clone(freeze: false)}
    x = EnvUtil.labeled_class("\u{1f4a9}").new
    assert_raise_with_message(ArgumentError, /\u{1f4a9}/) do
      Object.new.clone(freeze: x)
    end
  end

  def test_init_dupclone
    cls = Class.new do
      def initialize_clone(orig); throw :initialize_clone; end
      def initialize_dup(orig); throw :initialize_dup; end
    end

    obj = cls.new
    assert_throw(:initialize_clone) {obj.clone}
    assert_throw(:initialize_dup) {obj.dup}
  end

  def test_instance_of
    assert_raise(TypeError) { 1.instance_of?(1) }
  end

  def test_kind_of
    assert_raise(TypeError) { 1.kind_of?(1) }
  end

  def test_taint_frozen_obj
    o = Object.new
    o.freeze
    assert_raise(FrozenError) { o.taint }

    o = Object.new
    o.taint
    o.freeze
    assert_raise(FrozenError) { o.untaint }
  end

  def test_freeze_immediate
    assert_equal(true, 1.frozen?)
    1.freeze
    assert_equal(true, 1.frozen?)
    assert_equal(true, 2.frozen?)
    assert_equal(true, true.frozen?)
    assert_equal(true, false.frozen?)
    assert_equal(true, nil.frozen?)
  end

  def test_frozen_error_message
    name = "C\u{30c6 30b9 30c8}"
    klass = EnvUtil.labeled_class(name) {
      attr_accessor :foo
    }
    obj = klass.new.freeze
    assert_raise_with_message(FrozenError, /#{name}/) {
      obj.foo = 1
    }
  end

  def test_nil_to_f
    assert_equal(0.0, nil.to_f)
  end

  def test_not
    assert_equal(false, Object.new.send(:!))
    assert_equal(true, nil.send(:!))
  end

  def test_true_and
    assert_equal(true, true & true)
    assert_equal(true, true & 1)
    assert_equal(false, true & false)
    assert_equal(false, true & nil)
  end

  def test_true_or
    assert_equal(true, true | true)
    assert_equal(true, true | 1)
    assert_equal(true, true | false)
    assert_equal(true, true | nil)
  end

  def test_true_xor
    assert_equal(false, true ^ true)
    assert_equal(false, true ^ 1)
    assert_equal(true, true ^ false)
    assert_equal(true, true ^ nil)
  end

  def test_false_and
    assert_equal(false, false & true)
    assert_equal(false, false & 1)
    assert_equal(false, false & false)
    assert_equal(false, false & nil)
  end

  def test_false_or
    assert_equal(true, false | true)
    assert_equal(true, false | 1)
    assert_equal(false, false | false)
    assert_equal(false, false | nil)
  end

  def test_false_xor
    assert_equal(true, false ^ true)
    assert_equal(true, false ^ 1)
    assert_equal(false, false ^ false)
    assert_equal(false, false ^ nil)
  end

  def test_methods
    o = Object.new
    a1 = o.methods
    a2 = o.methods(false)

    def o.foo; end

    assert_equal([:foo], o.methods(true) - a1)
    assert_equal([:foo], o.methods(false) - a2)
  end

  def test_methods2
    c0 = Class.new
    c1 = Class.new(c0)
    c1.module_eval do
      public   ; def foo; end
      protected; def bar; end
      private  ; def baz; end
    end
    c2 = Class.new(c1)
    c2.module_eval do
      public   ; def foo2; end
      protected; def bar2; end
      private  ; def baz2; end
    end

    o0 = c0.new
    o2 = c2.new

    assert_equal([:baz, :baz2], (o2.private_methods - o0.private_methods).sort)
    assert_equal([:baz2], (o2.private_methods(false) - o0.private_methods(false)).sort)

    assert_equal([:bar, :bar2], (o2.protected_methods - o0.protected_methods).sort)
    assert_equal([:bar2], (o2.protected_methods(false) - o0.protected_methods(false)).sort)

    assert_equal([:foo, :foo2], (o2.public_methods - o0.public_methods).sort)
    assert_equal([:foo2], (o2.public_methods(false) - o0.public_methods(false)).sort)
  end

  def test_methods_prepend
    bug8044 = '[ruby-core:53207] [Bug #8044]'
    o = Object.new
    def o.foo; end
    assert_equal([:foo], o.methods(false))
    class << o; prepend Module.new; end
    assert_equal([:foo], o.methods(false), bug8044)
  end

  def test_instance_variable_get
    o = Object.new
    o.instance_eval { @foo = :foo }
    assert_equal(:foo, o.instance_variable_get(:@foo))
    assert_equal(nil, o.instance_variable_get(:@bar))
    assert_raise(NameError) { o.instance_variable_get('@') }
    assert_raise(NameError) { o.instance_variable_get(:'@') }
    assert_raise(NameError) { o.instance_variable_get(:foo) }
    assert_raise(NameError) { o.instance_variable_get("bar") }
    assert_raise(TypeError) { o.instance_variable_get(1) }

    n = Object.new
    def n.to_str; @count = defined?(@count) ? @count + 1 : 1; "@foo"; end
    def n.count; @count; end
    assert_equal(:foo, o.instance_variable_get(n))
    assert_equal(1, n.count)
  end

  def test_instance_variable_set
    o = Object.new
    o.instance_variable_set(:@foo, :foo)
    assert_equal(:foo, o.instance_eval { @foo })
    assert_raise(NameError) { o.instance_variable_set(:'@', 1) }
    assert_raise(NameError) { o.instance_variable_set('@', 1) }
    assert_raise(NameError) { o.instance_variable_set(:foo, 1) }
    assert_raise(NameError) { o.instance_variable_set("bar", 1) }
    assert_raise(TypeError) { o.instance_variable_set(1, 1) }

    n = Object.new
    def n.to_str; @count = defined?(@count) ? @count + 1 : 1; "@foo"; end
    def n.count; @count; end
    o.instance_variable_set(n, :bar)
    assert_equal(:bar, o.instance_eval { @foo })
    assert_equal(1, n.count)
  end

  def test_instance_variable_defined
    o = Object.new
    o.instance_eval { @foo = :foo }
    assert_equal(true, o.instance_variable_defined?(:@foo))
    assert_equal(false, o.instance_variable_defined?(:@bar))
    assert_raise(NameError) { o.instance_variable_defined?(:'@') }
    assert_raise(NameError) { o.instance_variable_defined?('@') }
    assert_raise(NameError) { o.instance_variable_defined?(:foo) }
    assert_raise(NameError) { o.instance_variable_defined?("bar") }
    assert_raise(TypeError) { o.instance_variable_defined?(1) }

    n = Object.new
    def n.to_str; @count = defined?(@count) ? @count + 1 : 1; "@foo"; end
    def n.count; @count; end
    assert_equal(true, o.instance_variable_defined?(n))
    assert_equal(1, n.count)
  end

  def test_remove_instance_variable
    { 'T_OBJECT' => Object.new,
      'T_CLASS,T_MODULE' => Class.new(Object),
      'generic ivar' => '',
    }.each do |desc, o|
      e = assert_raise(NameError, "#{desc} iv removal raises before set") do
        o.remove_instance_variable(:@foo)
      end
      assert_equal([o, :@foo], [e.receiver, e.name])
      o.instance_eval { @foo = :foo }
      assert_equal(:foo, o.remove_instance_variable(:@foo),
                   "#{desc} iv removal returns original value")
      assert_not_send([o, :instance_variable_defined?, :@foo],
                      "#{desc} iv removed successfully")
      e = assert_raise(NameError, "#{desc} iv removal raises after removal") do
        o.remove_instance_variable(:@foo)
      end
      assert_equal([o, :@foo], [e.receiver, e.name])
    end
  end

  def test_convert_string
    o = Object.new
    def o.to_s; 1; end
    assert_raise(TypeError) { String(o) }
    def o.to_s; "o"; end
    assert_equal("o", String(o))
    def o.to_str; "O"; end
    assert_equal("O", String(o))
    def o.respond_to?(*) false; end
    assert_raise(TypeError) { String(o) }
  end

  def test_convert_array
    o = Object.new
    def o.to_a; 1; end
    assert_raise(TypeError) { Array(o) }
    def o.to_a; [1]; end
    assert_equal([1], Array(o))
    def o.to_ary; [2]; end
    assert_equal([2], Array(o))
    def o.respond_to?(*) false; end
    assert_equal([o], Array(o))
  end

  def test_convert_hash
    assert_equal({}, Hash(nil))
    assert_equal({}, Hash([]))
    assert_equal({key: :value}, Hash(key: :value))
    assert_raise(TypeError) { Hash([1,2]) }
    assert_raise(TypeError) { Hash(Object.new) }
    o = Object.new
    def o.to_hash; {a: 1, b: 2}; end
    assert_equal({a: 1, b: 2}, Hash(o))
    def o.to_hash; 9; end
    assert_raise(TypeError) { Hash(o) }
  end

  def test_to_integer
    o = Object.new
    def o.to_i; nil; end
    assert_raise(TypeError) { Integer(o) }
    def o.to_i; 42; end
    assert_equal(42, Integer(o))
    def o.respond_to?(*) false; end
    assert_raise(TypeError) { Integer(o) }
  end

  class MyInteger
    def initialize(n); @num = n; end
    def to_int; @num; end
    def <=>(n); @num <=> n.to_int; end
    def <=(n); @num <= n.to_int; end
    def +(n); MyInteger.new(@num + n.to_int); end
  end

  def test_check_to_integer
    o1 = MyInteger.new(1)
    o9 = MyInteger.new(9)
    n = 0
    Range.new(o1, o9).step(2) {|x| n += x.to_int }
    assert_equal(1+3+5+7+9, n)
  end

  def test_redefine_method_under_verbose
    assert_in_out_err([], <<-INPUT, %w(2), /warning: method redefined; discarding old foo$/)
      $VERBOSE = true
      o = Object.new
      def o.foo; 1; end
      def o.foo; 2; end
      p o.foo
    INPUT
  end

  def test_redefine_method_which_may_case_serious_problem
    assert_in_out_err([], <<-INPUT, [], %r"warning: redefining `object_id' may cause serious problems$")
      $VERBOSE = false
      def (Object.new).object_id; end
    INPUT

    assert_in_out_err([], <<-INPUT, [], %r"warning: redefining `__send__' may cause serious problems$")
      $VERBOSE = false
      def (Object.new).__send__; end
    INPUT

    bug10421 = '[ruby-dev:48691] [Bug #10421]'
    assert_in_out_err([], <<-INPUT, ["1"], [], bug10421)
      $VERBOSE = false
      class C < BasicObject
        def object_id; 1; end
      end
      puts C.new.object_id
    INPUT
  end

  def test_remove_method
    c = Class.new
    c.freeze
    assert_raise(FrozenError) do
      c.instance_eval { remove_method(:foo) }
    end

    c = Class.new do
      def meth1; "meth" end
    end
    d = Class.new(c) do
      alias meth2 meth1
    end
    o1 = c.new
    assert_respond_to(o1, :meth1)
    assert_equal("meth", o1.meth1)
    o2 = d.new
    assert_respond_to(o2, :meth1)
    assert_equal("meth", o2.meth1)
    assert_respond_to(o2, :meth2)
    assert_equal("meth", o2.meth2)
    d.class_eval do
      remove_method :meth2
    end
    bug2202 = '[ruby-core:26074]'
    assert_raise(NoMethodError, bug2202) {o2.meth2}

    %w(object_id __send__ initialize).each do |m|
      assert_in_out_err([], <<-INPUT, %w(:ok), %r"warning: removing `#{m}' may cause serious problems$")
        $VERBOSE = false
        begin
          Class.new.instance_eval { remove_method(:#{m}) }
        rescue NameError
          p :ok
        end
      INPUT
    end

    m = "\u{30e1 30bd 30c3 30c9}"
    c = Class.new
    assert_raise_with_message(NameError, /#{m}/) do
      c.class_eval {remove_method m}
    end
    c = Class.new {
      define_method(m) {}
      remove_method(m)
    }
    assert_raise_with_message(NameError, /#{m}/) do
      c.class_eval {remove_method m}
    end
  end

  def test_method_missing
    assert_raise(ArgumentError) do
      1.instance_eval { method_missing }
    end

    c = Class.new
    c.class_eval do
      protected
      def foo; end
    end
    assert_raise(NoMethodError) do
      c.new.foo
    end

    assert_raise(NoMethodError) do
      1.instance_eval { method_missing(:method_missing) }
    end

    c.class_eval do
      undef_method(:method_missing)
    end

    assert_raise(ArgumentError) do
      c.new.method_missing
    end

    bug2494 = '[ruby-core:27219]'
    c = Class.new do
      def method_missing(meth, *args)
        super
      end
    end
    b = c.new
    foo rescue nil
    assert_nothing_raised(bug2494) {[b].flatten}
  end

  def test_respond_to_missing_string
    c = Class.new do
      def respond_to_missing?(id, priv)
        !(id !~ /\Agadzoks\d+\z/) ^ priv
      end
    end
    foo = c.new
    assert_equal(false, foo.respond_to?("gadzooks16"))
    assert_equal(true, foo.respond_to?("gadzooks17", true))
    assert_equal(true, foo.respond_to?("gadzoks16"))
    assert_equal(false, foo.respond_to?("gadzoks17", true))
  end

  def test_respond_to_missing
    c = Class.new do
      def respond_to_missing?(id, priv)
        if id == :foobar
          true
        else
          false
        end
      end
      def method_missing(id, *args)
        if id == :foobar
          return [:foo, *args]
        else
          super
        end
      end
    end

    foo = c.new
    assert_equal([:foo], foo.foobar);
    assert_equal([:foo, 1], foo.foobar(1));
    assert_equal([:foo, 1, 2, 3, 4, 5], foo.foobar(1, 2, 3, 4, 5));
    assert_respond_to(foo, :foobar)
    assert_not_respond_to(foo, :foobarbaz)
    assert_raise(NoMethodError) do
      foo.foobarbaz
    end

    foobar = foo.method(:foobar)
    assert_equal(-1, foobar.arity);
    assert_equal([:foo], foobar.call);
    assert_equal([:foo, 1], foobar.call(1));
    assert_equal([:foo, 1, 2, 3, 4, 5], foobar.call(1, 2, 3, 4, 5));
    assert_equal(foobar, foo.method(:foobar))
    assert_not_equal(foobar, c.new.method(:foobar))

    c = Class.new(c)
    assert_equal(false, c.method_defined?(:foobar))
    assert_raise(NameError, '[ruby-core:25748]') do
      c.instance_method(:foobar)
    end

    m = Module.new
    assert_equal(false, m.method_defined?(:foobar))
    assert_raise(NameError, '[ruby-core:25748]') do
      m.instance_method(:foobar)
    end
  end

  def test_implicit_respond_to
    bug5158 = '[ruby-core:38799]'

    p = Object.new

    called = []
    p.singleton_class.class_eval do
      define_method(:to_ary) do
        called << [:to_ary, bug5158]
      end
    end
    [[p]].flatten
    assert_equal([[:to_ary, bug5158]], called, bug5158)

    called = []
    p.singleton_class.class_eval do
      define_method(:respond_to?) do |*a|
        called << [:respond_to?, *a]
        false
      end
    end
    [[p]].flatten
    assert_equal([[:respond_to?, :to_ary, true]], called, bug5158)
  end

  def test_implicit_respond_to_arity_1
    p = Object.new

    called = []
    p.singleton_class.class_eval do
      define_method(:respond_to?) do |a|
        called << [:respond_to?, a]
        false
      end
    end
    [[p]].flatten
    assert_equal([[:respond_to?, :to_ary]], called, '[bug:6000]')
  end

  def test_implicit_respond_to_arity_3
    p = Object.new

    called = []
    p.singleton_class.class_eval do
      define_method(:respond_to?) do |a, b, c|
        called << [:respond_to?, a, b, c]
        false
      end
    end

    msg = 'respond_to? must accept 1 or 2 arguments (requires 3)'
    assert_raise_with_message(ArgumentError, msg, '[bug:6000]') do
      [[p]].flatten
    end
  end

  def test_method_missing_passed_block
    bug5731 = '[ruby-dev:44961]'

    c = Class.new do
      def method_missing(meth, *args) yield(meth, *args) end
    end
    a = c.new
    result = nil
    assert_nothing_raised(LocalJumpError, bug5731) do
      a.foo {|x| result = x}
    end
    assert_equal(:foo, result, bug5731)
    result = nil
    e = a.enum_for(:foo)
    assert_nothing_raised(LocalJumpError, bug5731) do
      e.each {|x| result = x}
    end
    assert_equal(:foo, result, bug5731)

    c = Class.new do
      def respond_to_missing?(id, priv)
        true
      end
      def method_missing(id, *args, &block)
        return block.call(:foo, *args)
      end
    end
    foo = c.new

    result = nil
    assert_nothing_raised(LocalJumpError, bug5731) do
      foo.foobar {|x| result = x}
    end
    assert_equal(:foo, result, bug5731)
    result = nil
    assert_nothing_raised(LocalJumpError, bug5731) do
      foo.enum_for(:foobar).each {|x| result = x}
    end
    assert_equal(:foo, result, bug5731)

    result = nil
    foobar = foo.method(:foobar)
    foobar.call {|x| result = x}
    assert_equal(:foo, result, bug5731)

    result = nil
    foobar = foo.method(:foobar)
    foobar.enum_for(:call).each {|x| result = x}
    assert_equal(:foo, result, bug5731)
  end

  def test_send_with_no_arguments
    assert_raise(ArgumentError) { 1.send }
  end

  def test_send_with_block
    x = :ng
    1.send(:times) { x = :ok }
    assert_equal(:ok, x)

    x = :ok
    o = Object.new
    def o.inspect
      yield if block_given?
      super
    end
    begin
      nil.public_send(o) { x = :ng }
    rescue TypeError
    end
    assert_equal(:ok, x)
  end

  def test_public_send
    c = Class.new do
      def pub
        :ok
      end

      def invoke(m)
        public_send(m)
      end

      protected
      def prot
        :ng
      end

      private
      def priv
        :ng
      end
    end.new
    assert_equal(:ok, c.public_send(:pub))
    assert_raise(NoMethodError) {c.public_send(:priv)}
    assert_raise(NoMethodError) {c.public_send(:prot)}
    assert_raise(NoMethodError) {c.invoke(:priv)}
    bug7499 = '[ruby-core:50489]'
    assert_raise(NoMethodError, bug7499) {c.invoke(:prot)}
  end

  def test_no_superclass_method
    bug2312 = '[ruby-dev:39581]'

    o = Object.new
    e = assert_raise(NoMethodError) {
      o.method(:__send__).call(:never_defined_test_no_superclass_method)
    }
    m1 = e.message
    assert_no_match(/no superclass method/, m1, bug2312)
    e = assert_raise(NoMethodError) {
      o.method(:__send__).call(:never_defined_test_no_superclass_method)
    }
    assert_equal(m1, e.message, bug2312)
    e = assert_raise(NoMethodError) {
      o.never_defined_test_no_superclass_method
    }
    assert_equal(m1, e.message, bug2312)
  end

  def test_superclass_method
    bug2312 = '[ruby-dev:39581]'
    assert_in_out_err(["-e", "module Enumerable;undef min;end; (1..2).min{}"],
                      "", [], /no superclass method/, bug2312)
  end

  def test_specific_eval_with_wrong_arguments
    assert_raise(ArgumentError) do
      1.instance_eval("foo") { foo }
    end

    assert_raise(ArgumentError) do
      1.instance_eval
    end

    assert_raise(ArgumentError) do
      1.instance_eval("", 1, 1, 1)
    end
  end

  class InstanceExec
    INSTANCE_EXEC = 123
  end

  def test_instance_exec
    x = 1.instance_exec(42) {|a| self + a }
    assert_equal(43, x)

    x = "foo".instance_exec("bar") {|a| self + a }
    assert_equal("foobar", x)

    assert_raise(NameError) do
      InstanceExec.new.instance_exec { INSTANCE_EXEC }
    end
  end

  def test_extend
    assert_raise(ArgumentError) do
      1.extend
    end
  end

  def test_untrusted
    verbose = $VERBOSE
    $VERBOSE = false
    begin
      obj = Object.new
      assert_equal(false, obj.untrusted?)
      assert_equal(false, obj.tainted?)
      obj.untrust
      assert_equal(true, obj.untrusted?)
      assert_equal(true, obj.tainted?)
      obj.trust
      assert_equal(false, obj.untrusted?)
      assert_equal(false, obj.tainted?)
      obj.taint
      assert_equal(true, obj.untrusted?)
      assert_equal(true, obj.tainted?)
      obj.untaint
      assert_equal(false, obj.untrusted?)
      assert_equal(false, obj.tainted?)
    ensure
      $VERBOSE = verbose
    end
  end

  def test_to_s
    x = Object.new
    x.taint
    s = x.to_s
    assert_equal(true, s.tainted?)

    x = eval(<<-EOS)
      class ToS\u{3042}
        new.to_s
      end
    EOS
    assert_match(/\bToS\u{3042}:/, x)

    name = "X".freeze
    x = Object.new.taint
    class<<x;self;end.class_eval {define_method(:to_s) {name}}
    assert_same(name, x.to_s)
    assert_not_predicate(name, :tainted?)
    assert_raise(FrozenError) {name.taint}
    assert_equal("X", [x].join(""))
    assert_not_predicate(name, :tainted?)
    assert_not_predicate(eval('"X".freeze'), :tainted?)
  end

  def test_inspect
    x = Object.new
    assert_match(/\A#<Object:0x\h+>\z/, x.inspect)

    x.instance_variable_set(:@ivar, :value)
    assert_match(/\A#<Object:0x\h+ @ivar=:value>\z/, x.inspect)

    x = Object.new
    x.instance_variable_set(:@recur, x)
    assert_match(/\A#<Object:0x\h+ @recur=#<Object:0x\h+ \.\.\.>>\z/, x.inspect)

    x = Object.new
    x.instance_variable_set(:@foo, "value")
    x.instance_variable_set(:@bar, 42)
    assert_match(/\A#<Object:0x\h+ (?:@foo="value", @bar=42|@bar=42, @foo="value")>\z/, x.inspect)

    # #inspect does not call #to_s anymore
    feature6130 = '[ruby-core:43238]'
    x = Object.new
    def x.to_s
      "to_s"
    end
    assert_match(/\A#<Object:0x\h+>\z/, x.inspect, feature6130)

    x = eval(<<-EOS)
      class Inspect\u{3042}
        new.inspect
      end
    EOS
    assert_match(/\bInspect\u{3042}:/, x)

    x = eval(<<-EOS)
      class Inspect\u{3042}
        def initialize
          @\u{3044} = 42
        end
        new
      end
    EOS
    assert_match(/\bInspect\u{3042}:.* @\u{3044}=42\b/, x.inspect)
    x.instance_variable_set("@\u{3046}".encode(Encoding::EUC_JP), 6)
    assert_match(/@\u{3046}=6\b/, x.inspect)
  end

  def test_singleton_class
    x = Object.new
    xs = class << x; self; end
    assert_equal(xs, x.singleton_class)

    y = Object.new
    ys = y.singleton_class
    assert_equal(class << y; self; end, ys)

    assert_equal(NilClass, nil.singleton_class)
    assert_equal(TrueClass, true.singleton_class)
    assert_equal(FalseClass, false.singleton_class)

    assert_raise(TypeError) do
      123.singleton_class
    end
    assert_raise(TypeError) do
      :foo.singleton_class
    end
  end

  def test_redef_method_missing
    bug5473 = '[ruby-core:40287]'
    ['ArgumentError.new("bug5473")', 'ArgumentError, "bug5473"', '"bug5473"'].each do |code|
      exc = code[/\A[A-Z]\w+/] || 'RuntimeError'
      assert_separately([], <<-SRC)
      $VERBOSE = nil
      class ::Object
        def method_missing(m, *a, &b)
          raise #{code}
        end
      end

      assert_raise_with_message(#{exc}, "bug5473", #{bug5473.dump}) {1.foo}
      SRC
    end
  end

  def assert_not_initialize_copy
    a = yield
    b = yield
    assert_nothing_raised("copy") {a.instance_eval {initialize_copy(b)}}
    c = a.dup.freeze
    assert_raise(FrozenError, "frozen") {c.instance_eval {initialize_copy(b)}}
    d = a.dup.trust
    [a, b, c, d]
  end

  def test_bad_initialize_copy
    assert_not_initialize_copy {Object.new}
    assert_not_initialize_copy {[].to_enum}
    assert_not_initialize_copy {Enumerator::Generator.new {}}
    assert_not_initialize_copy {Enumerator::Yielder.new {}}
    assert_not_initialize_copy {File.stat(__FILE__)}
    assert_not_initialize_copy {open(__FILE__)}.each(&:close)
    assert_not_initialize_copy {ARGF.class.new}
    assert_not_initialize_copy {Random.new}
    assert_not_initialize_copy {//}
    assert_not_initialize_copy {/.*/.match("foo")}
    st = Struct.new(:foo)
    assert_not_initialize_copy {st.new}
  end

  def test_type_error_message
    _issue = "Bug #7539"
    assert_raise_with_message(TypeError, "can't convert Array into Integer") {Integer([42])}
    assert_raise_with_message(TypeError, 'no implicit conversion of Array into Integer') {[].first([42])}
    assert_raise_with_message(TypeError, "can't convert Array into Rational") {Rational([42])}
  end

  def test_copied_ivar_memory_leak
    bug10191 = '[ruby-core:64700] [Bug #10191]'
    assert_no_memory_leak([], <<-"end;", <<-"end;", bug10191, timeout: 60, limit: 1.8)
      def (a = Object.new).set; @v = nil; end
      num = 500_000
    end;
      num.times {a.clone.set}
    end;
  end

  def test_clone_object_should_not_be_old
    assert_normal_exit <<-EOS, '[Bug #13775]'
      b = proc { }
      10.times do |i|
        b.clone
        GC.start
      end
    EOS
  end
end
