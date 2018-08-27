# frozen_string_literal: false
require 'test/unit'
require 'pp'

$m0 = Module.nesting

class TestModule < Test::Unit::TestCase
  def _wrap_assertion
    yield
  end

  def assert_method_defined?(klass, mid, message="")
    message = build_message(message, "#{klass}\##{mid} expected to be defined.")
    _wrap_assertion do
      klass.method_defined?(mid) or
        raise Test::Unit::AssertionFailedError, message, caller(3)
    end
  end

  def assert_method_not_defined?(klass, mid, message="")
    message = build_message(message, "#{klass}\##{mid} expected to not be defined.")
    _wrap_assertion do
      klass.method_defined?(mid) and
        raise Test::Unit::AssertionFailedError, message, caller(3)
    end
  end

  def setup
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  def teardown
    $VERBOSE = @verbose
  end

  def test_LT_0
    assert_equal true, String < Object
    assert_equal false, Object < String
    assert_nil String < Array
    assert_equal true, Array < Enumerable
    assert_equal false, Enumerable < Array
    assert_nil Proc < Comparable
    assert_nil Comparable < Proc
  end

  def test_GT_0
    assert_equal false, String > Object
    assert_equal true, Object > String
    assert_nil String > Array
    assert_equal false, Array > Enumerable
    assert_equal true, Enumerable > Array
    assert_nil Comparable > Proc
    assert_nil Proc > Comparable
  end

  def test_CMP_0
    assert_equal(-1, (String <=> Object))
    assert_equal 1, (Object <=> String)
    assert_nil(Array <=> String)
  end

  ExpectedException = NoMethodError

  # Support stuff

  module Mixin
    MIXIN = 1
    def mixin
    end
  end

  module User
    USER = 2
    include Mixin
    def user
    end

    def user2
    end
    protected :user2

    def user3
    end
    private :user3
  end

  module Other
    def other
    end
  end

  class AClass
    def AClass.cm1
      "cm1"
    end
    def AClass.cm2
      cm1 + "cm2" + cm3
    end
    def AClass.cm3
      "cm3"
    end

    private_class_method :cm1, "cm3"

    def aClass
      :aClass
    end

    def aClass1
      :aClass1
    end

    def aClass2
      :aClass2
    end

    private :aClass1
    protected :aClass2
  end

  class BClass < AClass
    def bClass1
      :bClass1
    end

    private

    def bClass2
      :bClass2
    end

    protected
    def bClass3
      :bClass3
    end
  end

  class CClass < BClass
    def self.cClass
    end
  end

  MyClass = AClass.clone
  class MyClass
    public_class_method :cm1
  end

  # -----------------------------------------------------------

  def test_CMP # '<=>'
    assert_equal( 0, Mixin <=> Mixin)
    assert_equal(-1, User <=> Mixin)
    assert_equal( 1, Mixin <=> User)

    assert_equal( 0, Object <=> Object)
    assert_equal(-1, String <=> Object)
    assert_equal( 1, Object <=> String)
  end

  def test_GE # '>='
    assert_operator(Mixin,    :>=, User)
    assert_operator(Mixin,    :>=, Mixin)
    assert_not_operator(User, :>=, Mixin)

    assert_operator(Object,     :>=, String)
    assert_operator(String,     :>=, String)
    assert_not_operator(String, :>=, Object)
  end

  def test_GT # '>'
    assert_operator(Mixin,     :>, User)
    assert_not_operator(Mixin, :>, Mixin)
    assert_not_operator(User,  :>, Mixin)

    assert_operator(Object,     :>, String)
    assert_not_operator(String, :>, String)
    assert_not_operator(String, :>, Object)
  end

  def test_LE # '<='
    assert_operator(User,      :<=, Mixin)
    assert_operator(Mixin,     :<=, Mixin)
    assert_not_operator(Mixin, :<=, User)

    assert_operator(String,     :<=, Object)
    assert_operator(String,     :<=, String)
    assert_not_operator(Object, :<=, String)
  end

  def test_LT # '<'
    assert_operator(User,      :<, Mixin)
    assert_not_operator(Mixin, :<, Mixin)
    assert_not_operator(Mixin, :<, User)

    assert_operator(String,     :<, Object)
    assert_not_operator(String, :<, String)
    assert_not_operator(Object, :<, String)
  end

  def test_VERY_EQUAL # '==='
    assert_operator(Object, :===, self)
    assert_operator(Test::Unit::TestCase, :===, self)
    assert_operator(TestModule, :===, self)
    assert_not_operator(String, :===, self)
  end

  def test_ancestors
    assert_equal([User, Mixin],      User.ancestors)
    assert_equal([Mixin],            Mixin.ancestors)

    ancestors = Object.ancestors
    mixins = ancestors - [Object, Kernel, BasicObject]
    mixins << JSON::Ext::Generator::GeneratorMethods::String if defined?(JSON::Ext::Generator::GeneratorMethods::String)
    assert_equal([Object, Kernel, BasicObject], ancestors - mixins)
    assert_equal([String, Comparable, Object, Kernel, BasicObject], String.ancestors - mixins)
  end

  CLASS_EVAL = 2
  @@class_eval = 'b'

  def test_class_eval
    Other.class_eval("CLASS_EVAL = 1")
    assert_equal(1, Other::CLASS_EVAL)
    assert_include(Other.constants, :CLASS_EVAL)
    assert_equal(2, Other.class_eval { CLASS_EVAL })

    Other.class_eval("@@class_eval = 'a'")
    assert_equal('a', Other.class_variable_get(:@@class_eval))
    assert_equal('b', Other.class_eval { @@class_eval })

    Other.class_eval do
      module_function

      def class_eval_test
        "foo"
      end
    end
    assert_equal("foo", Other.class_eval_test)

    assert_equal([Other], Other.class_eval { |*args| args })
  end

  def test_const_defined?
    assert_operator(Math, :const_defined?, :PI)
    assert_operator(Math, :const_defined?, "PI")
    assert_not_operator(Math, :const_defined?, :IP)
    assert_not_operator(Math, :const_defined?, "IP")
  end

  def each_bad_constants(m, &b)
    [
      "#<Class:0x7b8b718b>",
      ":Object",
      "",
      ":",
      ["String::", "[Bug #7573]"],
      "\u3042",
      "Name?",
    ].each do |name, msg|
      expected = "wrong constant name %s" % name
      msg = "#{msg}#{': ' if msg}wrong constant name #{name.dump}"
      assert_raise_with_message(NameError, expected, "#{msg} to #{m}") do
        yield name
      end
    end
  end

  def test_bad_constants_get
    each_bad_constants("get") {|name|
      Object.const_get name
    }
  end

  def test_bad_constants_defined
    each_bad_constants("defined?") {|name|
      Object.const_defined? name
    }
  end

  def test_leading_colons
    assert_equal Object, AClass.const_get('::Object')
  end

  def test_const_get
    assert_equal(Math::PI, Math.const_get("PI"))
    assert_equal(Math::PI, Math.const_get(:PI))

    n = Object.new
    def n.to_str; @count = defined?(@count) ? @count + 1 : 1; "PI"; end
    def n.count; @count; end
    assert_equal(Math::PI, Math.const_get(n))
    assert_equal(1, n.count)
  end

  def test_nested_get
    assert_equal Other, Object.const_get([self.class, Other].join('::'))
    assert_equal User::USER, self.class.const_get([User, 'USER'].join('::'))
  end

  def test_nested_get_symbol
    const = [self.class, Other].join('::').to_sym
    assert_raise(NameError) {Object.const_get(const)}

    const = [User, 'USER'].join('::').to_sym
    assert_raise(NameError) {self.class.const_get(const)}
  end

  def test_nested_get_const_missing
    classes = []
    klass = Class.new {
      define_singleton_method(:const_missing) { |name|
        classes << name
        klass
      }
    }
    klass.const_get("Foo::Bar::Baz")
    assert_equal [:Foo, :Bar, :Baz], classes
  end

  def test_nested_get_bad_class
    assert_raise(TypeError) do
      self.class.const_get([User, 'USER', 'Foo'].join('::'))
    end
  end

  def test_nested_defined
    assert_send([Object, :const_defined?, [self.class.name, 'Other'].join('::')])
    assert_send([self.class, :const_defined?, 'User::USER'])
    assert_not_send([self.class, :const_defined?, 'User::Foo'])
  end

  def test_nested_defined_symbol
    const = [self.class, Other].join('::').to_sym
    assert_raise(NameError) {Object.const_defined?(const)}

    const = [User, 'USER'].join('::').to_sym
    assert_raise(NameError) {self.class.const_defined?(const)}
  end

  def test_nested_defined_bad_class
    assert_raise(TypeError) do
      self.class.const_defined?('User::USER::Foo')
    end
  end

  def test_const_set
    assert_not_operator(Other, :const_defined?, :KOALA)
    Other.const_set(:KOALA, 99)
    assert_operator(Other, :const_defined?, :KOALA)
    assert_equal(99, Other::KOALA)
    Other.const_set("WOMBAT", "Hi")
    assert_equal("Hi", Other::WOMBAT)

    n = Object.new
    def n.to_str; @count = defined?(@count) ? @count + 1 : 1; "HOGE"; end
    def n.count; @count; end
    def n.count=(v); @count=v; end
    assert_not_operator(Other, :const_defined?, :HOGE)
    Other.const_set(n, 999)
    assert_equal(1, n.count)
    n.count = 0
    assert_equal(999, Other.const_get(n))
    assert_equal(1, n.count)
    n.count = 0
    assert_equal(true, Other.const_defined?(n))
    assert_equal(1, n.count)
  end

  def test_constants
    assert_equal([:MIXIN], Mixin.constants)
    assert_equal([:MIXIN, :USER], User.constants.sort)
  end

  def test_self_initialize_copy
    bug9535 = '[ruby-dev:47989] [Bug #9535]'
    m = Module.new do
      def foo
        :ok
      end
      initialize_copy(self)
    end
    assert_equal(:ok, Object.new.extend(m).foo, bug9535)
  end

  def test_initialize_copy_empty
    bug9813 = '[ruby-dev:48182] [Bug #9813]'
    m = Module.new do
      def x
      end
      const_set(:X, 1)
      @x = 2
    end
    assert_equal([:x], m.instance_methods)
    assert_equal([:@x], m.instance_variables)
    assert_equal([:X], m.constants)
    m.module_eval do
      initialize_copy(Module.new)
    end
    assert_empty(m.instance_methods, bug9813)
    assert_empty(m.instance_variables, bug9813)
    assert_empty(m.constants, bug9813)
  end

  def test_dup
    bug6454 = '[ruby-core:45132]'

    a = Module.new
    Other.const_set :BUG6454, a
    b = a.dup
    Other.const_set :BUG6454_dup, b

    assert_equal "TestModule::Other::BUG6454_dup", b.inspect, bug6454
  end

  def test_dup_anonymous
    bug6454 = '[ruby-core:45132]'

    a = Module.new
    original = a.inspect

    b = a.dup

    assert_not_equal original, b.inspect, bug6454
  end

  def test_public_include
    assert_nothing_raised('#8846') do
      Module.new.include(Module.new { def foo; end }).instance_methods == [:foo]
    end
  end

  def test_include_toplevel
    assert_separately([], <<-EOS)
      Mod = Module.new {def foo; :include_foo end}
      TOPLEVEL_BINDING.eval('include Mod')

      assert_equal(:include_foo, TOPLEVEL_BINDING.eval('foo'))
      assert_equal([Object, Mod], Object.ancestors.slice(0, 2))
    EOS
  end

  def test_include_with_no_args
    assert_raise(ArgumentError) { Module.new { include } }
  end

  def test_included_modules
    assert_equal([], Mixin.included_modules)
    assert_equal([Mixin], User.included_modules)

    mixins = Object.included_modules - [Kernel]
    mixins << JSON::Ext::Generator::GeneratorMethods::String if defined?(JSON::Ext::Generator::GeneratorMethods::String)
    assert_equal([Kernel], Object.included_modules - mixins)
    assert_equal([Comparable, Kernel], String.included_modules - mixins)
  end

  def test_instance_methods
    assert_equal([:user, :user2], User.instance_methods(false).sort)
    assert_equal([:user, :user2, :mixin].sort, User.instance_methods(true).sort)
    assert_equal([:mixin], Mixin.instance_methods)
    assert_equal([:mixin], Mixin.instance_methods(true))
    assert_equal([:cClass], (class << CClass; self; end).instance_methods(false))
    assert_equal([], (class << BClass; self; end).instance_methods(false))
    assert_equal([:cm2], (class << AClass; self; end).instance_methods(false))
    # Ruby 1.8 feature change:
    # #instance_methods includes protected methods.
    #assert_equal([:aClass], AClass.instance_methods(false))
    assert_equal([:aClass, :aClass2], AClass.instance_methods(false).sort)
    assert_equal([:aClass, :aClass2],
        (AClass.instance_methods(true) - Object.instance_methods(true)).sort)
  end

  def test_method_defined?
    assert !User.method_defined?(:wombat)
    assert User.method_defined?(:mixin)
    assert User.method_defined?(:user)
    assert User.method_defined?(:user2)
    assert !User.method_defined?(:user3)

    assert !User.method_defined?("wombat")
    assert User.method_defined?("mixin")
    assert User.method_defined?("user")
    assert User.method_defined?("user2")
    assert !User.method_defined?("user3")
  end

  def module_exec_aux
    Proc.new do
      def dynamically_added_method_3; end
    end
  end
  def module_exec_aux_2(&block)
    User.module_exec(&block)
  end

  def test_module_exec
    User.module_exec do
      def dynamically_added_method_1; end
    end
    assert_method_defined?(User, :dynamically_added_method_1)

    block = Proc.new do
      def dynamically_added_method_2; end
    end
    User.module_exec(&block)
    assert_method_defined?(User, :dynamically_added_method_2)

    User.module_exec(&module_exec_aux)
    assert_method_defined?(User, :dynamically_added_method_3)

    module_exec_aux_2 do
      def dynamically_added_method_4; end
    end
    assert_method_defined?(User, :dynamically_added_method_4)
  end

  def test_module_eval
    User.module_eval("MODULE_EVAL = 1")
    assert_equal(1, User::MODULE_EVAL)
    assert_include(User.constants, :MODULE_EVAL)
    User.instance_eval("remove_const(:MODULE_EVAL)")
    assert_not_include(User.constants, :MODULE_EVAL)
  end

  def test_name
    assert_equal("Integer", Integer.name)
    assert_equal("TestModule::Mixin",  Mixin.name)
    assert_equal("TestModule::User",   User.name)
  end

  def test_classpath
    m = Module.new
    n = Module.new
    m.const_set(:N, n)
    assert_nil(m.name)
    assert_nil(n.name)
    assert_equal([:N], m.constants)
    m.module_eval("module O end")
    assert_equal([:N, :O], m.constants.sort)
    m.module_eval("class C; end")
    assert_equal([:C, :N, :O], m.constants.sort)
    assert_nil(m::N.name)
    assert_match(/\A#<Module:.*>::O\z/, m::O.name)
    assert_match(/\A#<Module:.*>::C\z/, m::C.name)
    self.class.const_set(:M, m)
    prefix = self.class.name + "::M::"
    assert_equal(prefix+"N", m.const_get(:N).name)
    assert_equal(prefix+"O", m.const_get(:O).name)
    assert_equal(prefix+"C", m.const_get(:C).name)
  end

  def test_private_class_method
    assert_raise(ExpectedException) { AClass.cm1 }
    assert_raise(ExpectedException) { AClass.cm3 }
    assert_equal("cm1cm2cm3", AClass.cm2)
  end

  def test_private_instance_methods
    assert_equal([:aClass1], AClass.private_instance_methods(false))
    assert_equal([:bClass2], BClass.private_instance_methods(false))
    assert_equal([:aClass1, :bClass2],
        (BClass.private_instance_methods(true) -
         Object.private_instance_methods(true)).sort)
  end

  def test_protected_instance_methods
    assert_equal([:aClass2], AClass.protected_instance_methods)
    assert_equal([:bClass3], BClass.protected_instance_methods(false))
    assert_equal([:bClass3, :aClass2].sort,
                 (BClass.protected_instance_methods(true) -
                  Object.protected_instance_methods(true)).sort)
  end

  def test_public_class_method
    assert_equal("cm1",       MyClass.cm1)
    assert_equal("cm1cm2cm3", MyClass.cm2)
    assert_raise(ExpectedException) { eval "MyClass.cm3" }
  end

  def test_public_instance_methods
    assert_equal([:aClass],  AClass.public_instance_methods(false))
    assert_equal([:bClass1], BClass.public_instance_methods(false))
  end

  def test_s_constants
    c1 = Module.constants
    Object.module_eval "WALTER = 99"
    c2 = Module.constants
    assert_equal([:WALTER], c2 - c1)

    assert_equal([], Module.constants(true))
    assert_equal([], Module.constants(false))

    src = <<-INPUT
      ary = Module.constants
      module M
        WALTER = 99
      end
      class Module
        include M
      end
      p Module.constants - ary, Module.constants(true), Module.constants(false)
    INPUT
    assert_in_out_err([], src, %w([:M] [:WALTER] []), [])

    klass = Class.new do
      const_set(:X, 123)
    end
    assert_equal(false, klass.class_eval { Module.constants }.include?(:X))

    assert_equal(false, Complex.constants(false).include?(:compatible))
  end

  module M1
    $m1 = Module.nesting
    module M2
      $m2 = Module.nesting
    end
  end

  def test_s_nesting
    assert_equal([],                               $m0)
    assert_equal([TestModule::M1, TestModule],     $m1)
    assert_equal([TestModule::M1::M2,
                  TestModule::M1, TestModule],     $m2)
  end

  def test_s_new
    m = Module.new
    assert_instance_of(Module, m)
  end

  def test_freeze
    m = Module.new do
      def self.baz; end
      def bar; end
    end
    m.freeze
    assert_raise(RuntimeError) do
      m.module_eval do
        def foo; end
      end
    end
    assert_raise(RuntimeError) do
      m.__send__ :private, :bar
    end
    assert_raise(RuntimeError) do
      m.private_class_method :baz
    end
  end

  def test_attr_obsoleted_flag
    c = Class.new
    c.class_eval do
      def initialize
        @foo = :foo
        @bar = :bar
      end
      attr :foo, true
      attr :bar, false
    end
    o = c.new
    assert_equal(true, o.respond_to?(:foo))
    assert_equal(true, o.respond_to?(:foo=))
    assert_equal(true, o.respond_to?(:bar))
    assert_equal(false, o.respond_to?(:bar=))
  end

  def test_const_get_evaled
    c1 = Class.new
    c2 = Class.new(c1)

    eval("c1::Foo = :foo")
    assert_equal(:foo, c1::Foo)
    assert_equal(:foo, c2::Foo)
    assert_equal(:foo, c2.const_get(:Foo))
    assert_raise(NameError) { c2.const_get(:Foo, false) }

    eval("c1::Foo = :foo")
    assert_raise(NameError) { c1::Bar }
    assert_raise(NameError) { c2::Bar }
    assert_raise(NameError) { c2.const_get(:Bar) }
    assert_raise(NameError) { c2.const_get(:Bar, false) }
    assert_raise(NameError) { c2.const_get("Bar", false) }
    assert_raise(NameError) { c2.const_get("BaR11", false) }
    assert_raise(NameError) { Object.const_get("BaR11", false) }

    c1.instance_eval do
      def const_missing(x)
        x
      end
    end

    assert_equal(:Bar, c1::Bar)
    assert_equal(:Bar, c2::Bar)
    assert_equal(:Bar, c2.const_get(:Bar))
    assert_equal(:Bar, c2.const_get(:Bar, false))
    assert_equal(:Bar, c2.const_get("Bar"))
    assert_equal(:Bar, c2.const_get("Bar", false))

    v = c2.const_get("Bar11", false)
    assert_equal("Bar11".to_sym, v)

    assert_raise(NameError) { c1.const_get(:foo) }
  end

  def test_const_set_invalid_name
    c1 = Class.new
    assert_raise_with_message(NameError, /foo/) { c1.const_set(:foo, :foo) }
    assert_raise_with_message(NameError, /bar/) { c1.const_set("bar", :foo) }
    assert_raise_with_message(TypeError, /1/) { c1.const_set(1, :foo) }
    assert_nothing_raised(NameError) { c1.const_set("X\u{3042}", :foo) }
    assert_raise(NameError) { c1.const_set("X\u{3042}".encode("utf-16be"), :foo) }
    assert_raise(NameError) { c1.const_set("X\u{3042}".encode("utf-16le"), :foo) }
    assert_raise(NameError) { c1.const_set("X\u{3042}".encode("utf-32be"), :foo) }
    assert_raise(NameError) { c1.const_set("X\u{3042}".encode("utf-32le"), :foo) }
    cx = EnvUtil.labeled_class("X\u{3042}")
    assert_raise_with_message(TypeError, /X\u{3042}/) { c1.const_set(cx, :foo) }
  end

  def test_const_get_invalid_name
    c1 = Class.new
    assert_raise(NameError) { c1.const_get(:foo) }
    bug5084 = '[ruby-dev:44200]'
    assert_raise(TypeError, bug5084) { c1.const_get(1) }
    bug7574 = '[ruby-dev:46749]'
    assert_raise_with_message(NameError, "wrong constant name \"String\\u0000\"", bug7574) {
      Object.const_get("String\0")
    }
  end

  def test_const_defined_invalid_name
    c1 = Class.new
    assert_raise(NameError) { c1.const_defined?(:foo) }
    bug5084 = '[ruby-dev:44200]'
    assert_raise(TypeError, bug5084) { c1.const_defined?(1) }
    bug7574 = '[ruby-dev:46749]'
    assert_raise_with_message(NameError, "wrong constant name \"String\\u0000\"", bug7574) {
      Object.const_defined?("String\0")
    }
  end

  def test_const_get_no_inherited
    bug3422 = '[ruby-core:30719]'
    assert_in_out_err([], <<-INPUT, %w[1 NameError A], [], bug3422)
    BasicObject::A = 1
    puts [true, false].map {|inh|
      begin
        Object.const_get(:A, inh)
      rescue NameError => e
        [e.class, e.name]
      end
    }
    INPUT
  end

  def test_const_get_inherited
    bug3423 = '[ruby-core:30720]'
    assert_in_out_err([], <<-INPUT, %w[NameError A NameError A], [], bug3423)
    module Foo; A = 1; end
    class Object; include Foo; end
    class Bar; include Foo; end

    puts [Object, Bar].map {|klass|
      begin
        klass.const_get(:A, false)
      rescue NameError => e
        [e.class, e.name]
      end
    }
    INPUT
  end

  def test_const_in_module
    bug3423 = '[ruby-core:37698]'
    assert_in_out_err([], <<-INPUT, %w[ok], [], bug3423)
    module LangModuleSpecInObject
      module LangModuleTop
      end
    end
    include LangModuleSpecInObject
    module LangModuleTop
    end
    puts "ok" if LangModuleSpecInObject::LangModuleTop == LangModuleTop
    INPUT

    bug5264 = '[ruby-core:39227]'
    assert_in_out_err([], <<-'INPUT', [], [], bug5264)
    class A
      class X; end
    end
    class B < A
      module X; end
    end
    INPUT
  end

  def test_class_variable_get
    c = Class.new
    c.class_eval('@@foo = :foo')
    assert_equal(:foo, c.class_variable_get(:@@foo))
    assert_raise(NameError) { c.class_variable_get(:@@bar) } # c.f. instance_variable_get
    assert_raise(NameError) { c.class_variable_get(:'@@') }
    assert_raise(NameError) { c.class_variable_get('@@') }
    assert_raise(NameError) { c.class_variable_get(:foo) }
    assert_raise(NameError) { c.class_variable_get("bar") }
    assert_raise(TypeError) { c.class_variable_get(1) }

    n = Object.new
    def n.to_str; @count = defined?(@count) ? @count + 1 : 1; "@@foo"; end
    def n.count; @count; end
    assert_equal(:foo, c.class_variable_get(n))
    assert_equal(1, n.count)
  end

  def test_class_variable_set
    c = Class.new
    c.class_variable_set(:@@foo, :foo)
    assert_equal(:foo, c.class_eval('@@foo'))
    assert_raise(NameError) { c.class_variable_set(:'@@', 1) }
    assert_raise(NameError) { c.class_variable_set('@@', 1) }
    assert_raise(NameError) { c.class_variable_set(:foo, 1) }
    assert_raise(NameError) { c.class_variable_set("bar", 1) }
    assert_raise(TypeError) { c.class_variable_set(1, 1) }

    n = Object.new
    def n.to_str; @count = defined?(@count) ? @count + 1 : 1; "@@foo"; end
    def n.count; @count; end
    c.class_variable_set(n, :bar)
    assert_equal(:bar, c.class_eval('@@foo'))
    assert_equal(1, n.count)
  end

  def test_class_variable_defined
    c = Class.new
    c.class_eval('@@foo = :foo')
    assert_equal(true, c.class_variable_defined?(:@@foo))
    assert_equal(false, c.class_variable_defined?(:@@bar))
    assert_raise(NameError) { c.class_variable_defined?(:'@@') }
    assert_raise(NameError) { c.class_variable_defined?('@@') }
    assert_raise(NameError) { c.class_variable_defined?(:foo) }
    assert_raise(NameError) { c.class_variable_defined?("bar") }
    assert_raise(TypeError) { c.class_variable_defined?(1) }
    n = Object.new
    def n.to_str; @count = defined?(@count) ? @count + 1 : 1; "@@foo"; end
    def n.count; @count; end
    assert_equal(true, c.class_variable_defined?(n))
    assert_equal(1, n.count)
  end

  def test_remove_class_variable
    c = Class.new
    c.class_eval('@@foo = :foo')
    c.class_eval { remove_class_variable(:@@foo) }
    assert_equal(false, c.class_variable_defined?(:@@foo))
    assert_raise(NameError) do
      c.class_eval { remove_class_variable(:@var) }
    end
  end

  def test_export_method
    m = Module.new
    assert_raise(NameError) do
      m.instance_eval { public(:foo) }
    end
  end

  def test_attr
    assert_in_out_err([], <<-INPUT, %w(nil))
      $VERBOSE = true
      c = Class.new
      c.instance_eval do
        private
        attr_reader :foo
      end
      o = c.new
      p(o.instance_eval { foo })
    INPUT

    c = Class.new
    assert_raise(NameError) do
      c.instance_eval { attr_reader :"." }
    end
  end

  def test_undef
    c = Class.new
    assert_raise(NameError) do
      c.instance_eval { undef_method(:foo) }
    end

    m = Module.new
    assert_raise(NameError) do
      m.instance_eval { undef_method(:foo) }
    end

    o = Object.new
    assert_raise(NameError) do
      class << o; self; end.instance_eval { undef_method(:foo) }
    end

    %w(object_id __send__ initialize).each do |n|
      assert_in_out_err([], <<-INPUT, [], %r"warning: undefining `#{n}' may cause serious problems$")
        $VERBOSE = false
        Class.new.instance_eval { undef_method(:#{n}) }
      INPUT
    end
  end

  def test_alias
    m = Module.new
    assert_raise(NameError) do
      m.class_eval { alias foo bar }
    end

    assert_in_out_err([], <<-INPUT, %w(2), /discarding old foo$/)
      $VERBOSE = true
      c = Class.new
      c.class_eval do
        def foo; 1; end
        def bar; 2; end
      end
      c.class_eval { alias foo bar }
      p c.new.foo
    INPUT
  end

  def test_mod_constants
    m = Module.new
    m.const_set(:Foo, :foo)
    assert_equal([:Foo], m.constants(true))
    assert_equal([:Foo], m.constants(false))
    m.instance_eval { remove_const(:Foo) }
  end

  class Bug9413
    class << self
      Foo = :foo
    end
  end

  def test_singleton_constants
    bug9413 = '[ruby-core:59763] [Bug #9413]'
    c = Bug9413.singleton_class
    assert_include(c.constants(true), :Foo, bug9413)
    assert_include(c.constants(false), :Foo, bug9413)
  end

  def test_frozen_module
    m = Module.new
    m.freeze
    assert_raise(RuntimeError) do
      m.instance_eval { undef_method(:foo) }
    end
  end

  def test_frozen_class
    c = Class.new
    c.freeze
    assert_raise(RuntimeError) do
      c.instance_eval { undef_method(:foo) }
    end
  end

  def test_frozen_singleton_class
    klass = Class.new
    o = klass.new
    c = class << o; self; end
    c.freeze
    assert_raise_with_message(RuntimeError, /frozen/) do
      c.instance_eval { undef_method(:foo) }
    end
    klass.class_eval do
      def self.foo
      end
    end
  end

  def test_method_defined
    c = Class.new
    c.class_eval do
      def foo; end
      def bar; end
      def baz; end
      public :foo
      protected :bar
      private :baz
    end

    assert_equal(true, c.public_method_defined?(:foo))
    assert_equal(false, c.public_method_defined?(:bar))
    assert_equal(false, c.public_method_defined?(:baz))

    # Test if string arguments are converted to symbols
    assert_equal(true, c.public_method_defined?("foo"))
    assert_equal(false, c.public_method_defined?("bar"))
    assert_equal(false, c.public_method_defined?("baz"))

    assert_equal(false, c.protected_method_defined?(:foo))
    assert_equal(true, c.protected_method_defined?(:bar))
    assert_equal(false, c.protected_method_defined?(:baz))

    # Test if string arguments are converted to symbols
    assert_equal(false, c.protected_method_defined?("foo"))
    assert_equal(true, c.protected_method_defined?("bar"))
    assert_equal(false, c.protected_method_defined?("baz"))

    assert_equal(false, c.private_method_defined?(:foo))
    assert_equal(false, c.private_method_defined?(:bar))
    assert_equal(true, c.private_method_defined?(:baz))

    # Test if string arguments are converted to symbols
    assert_equal(false, c.private_method_defined?("foo"))
    assert_equal(false, c.private_method_defined?("bar"))
    assert_equal(true, c.private_method_defined?("baz"))
  end

  def test_top_public_private
    assert_in_out_err([], <<-INPUT, %w([:foo] [:bar]), [])
      private
      def foo; :foo; end
      public
      def bar; :bar; end
      p self.private_methods.grep(/^foo$|^bar$/)
      p self.methods.grep(/^foo$|^bar$/)
    INPUT
  end

  def test_append_features
    t = nil
    m = Module.new
    m.module_eval do
      def foo; :foo; end
    end
    class << m; self; end.class_eval do
      define_method(:append_features) do |mod|
        t = mod
        super(mod)
      end
    end

    m2 = Module.new
    m2.module_eval { include(m) }
    assert_equal(m2, t)

    o = Object.new
    o.extend(m2)
    assert_equal(true, o.respond_to?(:foo))
  end

  def test_append_features_raise
    m = Module.new
    m.module_eval do
      def foo; :foo; end
    end
    class << m; self; end.class_eval do
      define_method(:append_features) {|mod| raise }
    end

    m2 = Module.new
    assert_raise(RuntimeError) do
      m2.module_eval { include(m) }
    end

    o = Object.new
    o.extend(m2)
    assert_equal(false, o.respond_to?(:foo))
  end

  def test_append_features_type_error
    assert_raise(TypeError) do
      Module.new.instance_eval { append_features(1) }
    end
  end

  def test_included
    m = Module.new
    m.module_eval do
      def foo; :foo; end
    end
    class << m; self; end.class_eval do
      define_method(:included) {|mod| raise }
    end

    m2 = Module.new
    assert_raise(RuntimeError) do
      m2.module_eval { include(m) }
    end

    o = Object.new
    o.extend(m2)
    assert_equal(true, o.respond_to?(:foo))
  end

  def test_cyclic_include
    m1 = Module.new
    m2 = Module.new
    m1.instance_eval { include(m2) }
    assert_raise(ArgumentError) do
      m2.instance_eval { include(m1) }
    end
  end

  def test_include_p
    m = Module.new
    c1 = Class.new
    c1.instance_eval { include(m) }
    c2 = Class.new(c1)
    assert_equal(true, c1.include?(m))
    assert_equal(true, c2.include?(m))
    assert_equal(false, m.include?(m))
  end

  def test_send
    a = AClass.new
    assert_equal(:aClass, a.__send__(:aClass))
    assert_equal(:aClass1, a.__send__(:aClass1))
    assert_equal(:aClass2, a.__send__(:aClass2))
    b = BClass.new
    assert_equal(:aClass, b.__send__(:aClass))
    assert_equal(:aClass1, b.__send__(:aClass1))
    assert_equal(:aClass2, b.__send__(:aClass2))
    assert_equal(:bClass1, b.__send__(:bClass1))
    assert_equal(:bClass2, b.__send__(:bClass2))
    assert_equal(:bClass3, b.__send__(:bClass3))
  end


  def test_nonascii_name
    c = eval("class ::C\u{df}; self; end")
    assert_equal("C\u{df}", c.name, '[ruby-core:24600]')
    c = eval("class C\u{df}; self; end")
    assert_equal("TestModule::C\u{df}", c.name, '[ruby-core:24600]')
    c = Module.new.module_eval("class X\u{df} < Module; self; end")
    assert_match(/::X\u{df}:/, c.new.to_s)
  end

  def test_method_added
    memo = []
    mod = Module.new do
      mod = self
      (class << self ; self ; end).class_eval do
        define_method :method_added do |sym|
          memo << sym
          memo << mod.instance_methods(false)
          memo << (mod.instance_method(sym) rescue nil)
        end
      end
      def f
      end
      alias g f
      attr_reader :a
      attr_writer :a
    end
    assert_equal :f, memo.shift
    assert_equal [:f], memo.shift, '[ruby-core:25536]'
    assert_equal mod.instance_method(:f), memo.shift
    assert_equal :g, memo.shift
    assert_equal [:f, :g].sort, memo.shift.sort
    assert_equal mod.instance_method(:f), memo.shift
    assert_equal :a, memo.shift
    assert_equal [:f, :g, :a].sort, memo.shift.sort
    assert_equal mod.instance_method(:a), memo.shift
    assert_equal :a=, memo.shift
    assert_equal [:f, :g, :a, :a=].sort, memo.shift.sort
    assert_equal mod.instance_method(:a=), memo.shift
  end

  def test_method_undefined
    added = []
    undefed = []
    removed = []
    mod = Module.new do
      mod = self
      def f
      end
      (class << self ; self ; end).class_eval do
        define_method :method_added do |sym|
          added << sym
        end
        define_method :method_undefined do |sym|
          undefed << sym
        end
        define_method :method_removed do |sym|
          removed << sym
        end
      end
    end
    assert_method_defined?(mod, :f)
    mod.module_eval do
      undef :f
    end
    assert_equal [], added
    assert_equal [:f], undefed
    assert_equal [], removed
  end

  def test_method_removed
    added = []
    undefed = []
    removed = []
    mod = Module.new do
      mod = self
      def f
      end
      (class << self ; self ; end).class_eval do
        define_method :method_added do |sym|
          added << sym
        end
        define_method :method_undefined do |sym|
          undefed << sym
        end
        define_method :method_removed do |sym|
          removed << sym
        end
      end
    end
    assert_method_defined?(mod, :f)
    mod.module_eval do
      remove_method :f
    end
    assert_equal [], added
    assert_equal [], undefed
    assert_equal [:f], removed
  end

  def test_method_redefinition
    feature2155 = '[ruby-dev:39400]'

    line = __LINE__+4
    stderr = EnvUtil.verbose_warning do
      Module.new do
        def foo; end
        def foo; end
      end
    end
    assert_match(/:#{line}: warning: method redefined; discarding old foo/, stderr)
    assert_match(/:#{line-1}: warning: previous definition of foo/, stderr, feature2155)

    assert_warning '' do
      Module.new do
        def foo; end
        alias bar foo
        def foo; end
      end
    end

    assert_warning '' do
      Module.new do
        def foo; end
        alias bar foo
        alias bar foo
      end
    end

    line = __LINE__+4
    stderr = EnvUtil.verbose_warning do
      Module.new do
        define_method(:foo) do end
        def foo; end
      end
    end
    assert_match(/:#{line}: warning: method redefined; discarding old foo/, stderr)
    assert_match(/:#{line-1}: warning: previous definition of foo/, stderr, feature2155)

    assert_warning '' do
      Module.new do
        define_method(:foo) do end
        alias bar foo
        alias bar foo
      end
    end

    assert_warning('', '[ruby-dev:39397]') do
      Module.new do
        module_function
        def foo; end
        module_function :foo
      end
    end

    assert_warning '' do
      Module.new do
        def foo; end
        undef foo
      end
    end

    stderr = EnvUtil.verbose_warning do
      Module.new do
        def foo; end
        mod = self
        c = Class.new do
          include mod
        end
        c.new.foo
        def foo; end
      end
    end
    assert_match(/: warning: method redefined; discarding old foo/, stderr)
    assert_match(/: warning: previous definition of foo/, stderr)
  end

  def test_protected_singleton_method
    klass = Class.new
    x = klass.new
    class << x
      protected

      def foo
      end
    end
    assert_raise(NoMethodError) do
      x.foo
    end
    klass.send(:define_method, :bar) do
      x.foo
    end
    assert_nothing_raised do
      x.bar
    end
    y = klass.new
    assert_raise(NoMethodError) do
      y.bar
    end
  end

  def test_uninitialized_toplevel_constant
    bug3123 = '[ruby-dev:40951]'
    e = assert_raise(NameError) {eval("Bug3123", TOPLEVEL_BINDING)}
    assert_not_match(/Object::/, e.message, bug3123)
  end

  def test_attr_inherited_visibility
    bug3406 = '[ruby-core:30638]'
    c = Class.new do
      class << self
        private
        def attr_accessor(*); super; end
      end
      attr_accessor :x
    end.new
    assert_nothing_raised(bug3406) {c.x = 1}
    assert_equal(1, c.x, bug3406)
  end

  def test_attr_writer_with_no_arguments
    bug8540 = "[ruby-core:55543]"
    c = Class.new do
      attr_writer :foo
    end
    assert_raise(ArgumentError, bug8540) { c.new.send :foo= }
  end

  def test_private_constant_in_class
    c = Class.new
    c.const_set(:FOO, "foo")
    assert_equal("foo", c::FOO)
    c.private_constant(:FOO)
    e = assert_raise(NameError) {c::FOO}
    assert_equal(c, e.receiver)
    assert_equal(:FOO, e.name)
    assert_equal("foo", c.class_eval("FOO"))
    assert_equal("foo", c.const_get("FOO"))
    $VERBOSE, verbose = nil, $VERBOSE
    c.const_set(:FOO, "foo")
    $VERBOSE = verbose
    e = assert_raise(NameError) {c::FOO}
    assert_equal(c, e.receiver)
    assert_equal(:FOO, e.name)
    e = assert_raise_with_message(NameError, /#{c}::FOO/) do
      Class.new(c)::FOO
    end
    assert_equal(c, e.receiver)
    assert_equal(:FOO, e.name)
  end

  def test_private_constant_in_module
    m = Module.new
    m.const_set(:FOO, "foo")
    assert_equal("foo", m::FOO)
    m.private_constant(:FOO)
    e = assert_raise(NameError) {m::FOO}
    assert_equal(m, e.receiver)
    assert_equal(:FOO, e.name)
    assert_equal("foo", m.class_eval("FOO"))
    assert_equal("foo", m.const_get("FOO"))
    $VERBOSE, verbose = nil, $VERBOSE
    m.const_set(:FOO, "foo")
    $VERBOSE = verbose
    e = assert_raise(NameError) {m::FOO}
    assert_equal(m, e.receiver)
    assert_equal(:FOO, e.name)
    e = assert_raise(NameError, /#{m}::FOO/) do
      Module.new {include m}::FOO
    end
    assert_equal(m, e.receiver)
    assert_equal(:FOO, e.name)
    e = assert_raise(NameError, /#{m}::FOO/) do
      Class.new {include m}::FOO
    end
    assert_equal(m, e.receiver)
    assert_equal(:FOO, e.name)
  end

  def test_private_constant2
    c = Class.new
    c.const_set(:FOO, "foo")
    c.const_set(:BAR, "bar")
    assert_equal("foo", c::FOO)
    assert_equal("bar", c::BAR)
    c.private_constant(:FOO, :BAR)
    assert_raise(NameError) { c::FOO }
    assert_raise(NameError) { c::BAR }
    assert_equal("foo", c.class_eval("FOO"))
    assert_equal("bar", c.class_eval("BAR"))
  end

  def test_private_constant_with_no_args
    assert_in_out_err([], <<-RUBY, [], ["-:3: warning: private_constant with no argument is just ignored"])
      $-w = true
      class X
        private_constant
      end
    RUBY
  end

  class PrivateClass
  end
  private_constant :PrivateClass

  def test_define_module_under_private_constant
    assert_raise(NameError) do
      eval %q{class TestModule::PrivateClass; end}
    end
    assert_raise(NameError) do
      eval %q{module TestModule::PrivateClass::TestModule; end}
    end
    eval %q{class PrivateClass; end}
    eval %q{module PrivateClass::TestModule; end}
    assert_instance_of(Module, PrivateClass::TestModule)
    PrivateClass.class_eval { remove_const(:TestModule) }
  end

  def test_public_constant
    c = Class.new
    c.const_set(:FOO, "foo")
    assert_equal("foo", c::FOO)
    c.private_constant(:FOO)
    assert_raise(NameError) { c::FOO }
    assert_equal("foo", c.class_eval("FOO"))
    c.public_constant(:FOO)
    assert_equal("foo", c::FOO)
  end

  def test_deprecate_constant
    c = Class.new
    c.const_set(:FOO, "foo")
    c.deprecate_constant(:FOO)
    assert_warn(/deprecated/) {c::FOO}
    assert_warn(/#{c}::FOO is deprecated/) {Class.new(c)::FOO}
    bug12382 = '[ruby-core:75505] [Bug #12382]'
    assert_warn(/deprecated/, bug12382) {c.class_eval "FOO"}
  end

  def test_constants_with_private_constant
    assert_not_include(::TestModule.constants, :PrivateClass)
    assert_not_include(::TestModule.constants(true), :PrivateClass)
    assert_not_include(::TestModule.constants(false), :PrivateClass)
  end

  def test_toplevel_private_constant
    src = <<-INPUT
      class Object
        private_constant :Object
      end
      p Object
      begin
        p ::Object
      rescue
        p :ok
      end
    INPUT
    assert_in_out_err([], src, %w(Object :ok), [])
  end

  def test_private_constants_clear_inlinecache
    bug5702 = '[ruby-dev:44929]'
    src = <<-INPUT
    class A
      C = :Const
      def self.get_C
        A::C
      end
      # fill cache
      A.get_C
      private_constant :C, :D rescue nil
      begin
        A.get_C
      rescue NameError
        puts "A.get_C"
      end
    end
    INPUT
    assert_in_out_err([], src, %w(A.get_C), [], bug5702)
  end

  def test_constant_lookup_in_method_defined_by_class_eval
    src = <<-INPUT
      class A
        B = 42
      end

      A.class_eval do
        def self.f
          B
        end

        def f
          B
        end
      end

      begin
        A.f
      rescue NameError
        puts "A.f"
      end
      begin
        A.new.f
      rescue NameError
        puts "A.new.f"
      end
    INPUT
    assert_in_out_err([], src, %w(A.f A.new.f), [])
  end

  def test_constant_lookup_in_toplevel_class_eval
    src = <<-INPUT
      module X
        A = 123
      end
      begin
        X.class_eval { A }
      rescue NameError => e
        puts e
      end
    INPUT
    assert_in_out_err([], src, ["uninitialized constant A"], [])
  end

  def test_constant_lookup_in_module_in_class_eval
    src = <<-INPUT
      class A
        B = 42
      end

      A.class_eval do
        module C
          begin
            B
          rescue NameError
            puts "NameError"
          end
        end
      end
    INPUT
    assert_in_out_err([], src, ["NameError"], [])
  end

  module M0
    def m1; [:M0] end
  end
  module M1
    def m1; [:M1, *super] end
  end
  module M2
    def m1; [:M2, *super] end
  end
  M3 = Module.new do
    def m1; [:M3, *super] end
  end
  module M4
    def m1; [:M4, *super] end
  end
  class C
    def m1; end
  end
  class C0 < C
    include M0
    prepend M1
    def m1; [:C0, *super] end
  end
  class C1 < C0
    prepend M2, M3
    include M4
    def m1; [:C1, *super] end
  end

  def test_prepend
    obj = C0.new
    expected = [:M1,:C0,:M0]
    assert_equal(expected, obj.m1)
    obj = C1.new
    expected = [:M2,:M3,:C1,:M4,:M1,:C0,:M0]
    assert_equal(expected, obj.m1)
  end

  def test_public_prepend
    assert_nothing_raised('#8846') do
      Class.new.prepend(Module.new)
    end
  end

  def test_prepend_CMP
    bug11878 = '[ruby-core:72493] [Bug #11878]'
    assert_equal(-1, C1 <=> M2)
    assert_equal(+1, M2 <=> C1, bug11878)
  end

  def test_prepend_inheritance
    bug6654 = '[ruby-core:45914]'
    a = labeled_module("a")
    b = labeled_module("b") {include a}
    c = labeled_class("c") {prepend b}
    assert_operator(c, :<, b, bug6654)
    assert_operator(c, :<, a, bug6654)
    bug8357 = '[ruby-core:54736] [Bug #8357]'
    b = labeled_module("b") {prepend a}
    c = labeled_class("c") {include b}
    assert_operator(c, :<, b, bug8357)
    assert_operator(c, :<, a, bug8357)
    bug8357 = '[ruby-core:54742] [Bug #8357]'
    assert_kind_of(b, c.new, bug8357)
  end

  def test_prepend_instance_methods
    bug6655 = '[ruby-core:45915]'
    assert_equal(Object.instance_methods, Class.new {prepend Module.new}.instance_methods, bug6655)
  end

  def test_prepend_singleton_methods
    o = Object.new
    o.singleton_class.class_eval {prepend Module.new}
    assert_equal([], o.singleton_methods)
  end

  def test_prepend_remove_method
    c = Class.new do
      prepend Module.new {def foo; end}
    end
    assert_raise(NameError) do
      c.class_eval do
        remove_method(:foo)
      end
    end
    c.class_eval do
      def foo; end
    end
    removed = nil
    c.singleton_class.class_eval do
      define_method(:method_removed) {|id| removed = id}
    end
    assert_nothing_raised(NoMethodError, NameError, '[Bug #7843]') do
      c.class_eval do
        remove_method(:foo)
      end
    end
    assert_equal(:foo, removed)
  end

  def test_prepend_class_ancestors
    bug6658 = '[ruby-core:45919]'
    m = labeled_module("m")
    c = labeled_class("c") {prepend m}
    assert_equal([m, c], c.ancestors[0, 2], bug6658)

    bug6662 = '[ruby-dev:45868]'
    c2 = labeled_class("c2", c)
    anc = c2.ancestors
    assert_equal([c2, m, c, Object], anc[0..anc.index(Object)], bug6662)
  end

  def test_prepend_module_ancestors
    bug6659 = '[ruby-dev:45861]'
    m0 = labeled_module("m0") {def x; [:m0, *super] end}
    m1 = labeled_module("m1") {def x; [:m1, *super] end; prepend m0}
    m2 = labeled_module("m2") {def x; [:m2, *super] end; prepend m1}
    c0 = labeled_class("c0") {def x; [:c0] end}
    c1 = labeled_class("c1") {def x; [:c1] end; prepend m2}
    c2 = labeled_class("c2", c0) {def x; [:c2, *super] end; include m2}

    assert_equal([m0, m1], m1.ancestors, bug6659)

    bug6662 = '[ruby-dev:45868]'
    assert_equal([m0, m1, m2], m2.ancestors, bug6662)
    assert_equal([m0, m1, m2, c1], c1.ancestors[0, 4], bug6662)
    assert_equal([:m0, :m1, :m2, :c1], c1.new.x)
    assert_equal([c2, m0, m1, m2, c0], c2.ancestors[0, 5], bug6662)
    assert_equal([:c2, :m0, :m1, :m2, :c0], c2.new.x)

    m3 = labeled_module("m3") {include m1; prepend m1}
    assert_equal([m3, m0, m1], m3.ancestors)
    m3 = labeled_module("m3") {prepend m1; include m1}
    assert_equal([m0, m1, m3], m3.ancestors)
    m3 = labeled_module("m3") {prepend m1; prepend m1}
    assert_equal([m0, m1, m3], m3.ancestors)
    m3 = labeled_module("m3") {include m1; include m1}
    assert_equal([m3, m0, m1], m3.ancestors)
  end

  def labeled_module(name, &block)
    EnvUtil.labeled_module(name, &block)
  end

  def labeled_class(name, superclass = Object, &block)
    EnvUtil.labeled_class(name, superclass, &block)
  end

  def test_prepend_instance_methods_false
    bug6660 = '[ruby-dev:45863]'
    assert_equal([:m1], Class.new{ prepend Module.new; def m1; end }.instance_methods(false), bug6660)
    assert_equal([:m1], Class.new(Class.new{def m2;end}){ prepend Module.new; def m1; end }.instance_methods(false), bug6660)
  end

  def test_cyclic_prepend
    bug7841 = '[ruby-core:52205] [Bug #7841]'
    m1 = Module.new
    m2 = Module.new
    m1.instance_eval { prepend(m2) }
    assert_raise(ArgumentError, bug7841) do
      m2.instance_eval { prepend(m1) }
    end
  end

  def test_prepend_optmethod
    bug7983 = '[ruby-dev:47124] [Bug #7983]'
    assert_separately [], %{
      module M
        def /(other)
          to_f / other
        end
      end
      Integer.send(:prepend, M)
      assert_equal(0.5, 1 / 2, "#{bug7983}")
    }
    assert_equal(0, 1 / 2)
  end

  def test_redefine_optmethod_after_prepend
    bug11826 = '[ruby-core:72188] [Bug #11826]'
    assert_separately [], %{
      module M
      end
      class Integer
        prepend M
        def /(other)
          quo(other)
        end
      end
      assert_equal(1 / 2r, 1 / 2, "#{bug11826}")
    }, ignore_stderr: true
    assert_equal(0, 1 / 2)
  end

  def test_override_optmethod_after_prepend
    bug11836 = '[ruby-core:72226] [Bug #11836]'
    assert_separately [], %{
      module M
      end
      class Integer
        prepend M
      end
      module M
        def /(other)
          quo(other)
        end
      end
      assert_equal(1 / 2r, 1 / 2, "#{bug11836}")
    }, ignore_stderr: true
    assert_equal(0, 1 / 2)
  end

  def test_prepend_visibility
    bug8005 = '[ruby-core:53106] [Bug #8005]'
    c = Class.new do
      prepend Module.new {}
      def foo() end
      protected :foo
    end
    a = c.new
    assert_respond_to a, [:foo, true], bug8005
    assert_nothing_raised(NoMethodError, bug8005) {a.send :foo}
  end

  def test_prepend_visibility_inherited
    bug8238 = '[ruby-core:54105] [Bug #8238]'
    assert_separately [], <<-"end;", timeout: 20
      class A
        def foo() A; end
        private :foo
      end
      class B < A
        public :foo
        prepend Module.new
      end
      assert_equal(A, B.new.foo, "#{bug8238}")
    end;
  end

  def test_prepend_included_modules
    bug8025 = '[ruby-core:53158] [Bug #8025]'
    mixin = labeled_module("mixin")
    c = labeled_module("c") {prepend mixin}
    im = c.included_modules
    assert_not_include(im, c, bug8025)
    assert_include(im, mixin, bug8025)
    c1 = labeled_class("c1") {prepend mixin}
    c2 = labeled_class("c2", c1)
    im = c2.included_modules
    assert_not_include(im, c1, bug8025)
    assert_not_include(im, c2, bug8025)
    assert_include(im, mixin, bug8025)
  end

  def test_prepend_super_in_alias
    bug7842 = '[Bug #7842]'

    p = labeled_module("P") do
      def m; "P"+super; end
    end
    a = labeled_class("A") do
      def m; "A"; end
    end
    b = labeled_class("B", a) do
      def m; "B"+super; end
      alias m2 m
      prepend p
      alias m3 m
    end
    assert_equal("BA", b.new.m2, bug7842)
    assert_equal("PBA", b.new.m3, bug7842)
  end

  def test_include_super_in_alias
    bug9236 = '[Bug #9236]'

    fun = labeled_module("Fun") do
      def hello
        orig_hello
      end
    end

    m1 = labeled_module("M1") do
      def hello
        'hello!'
      end
    end

    m2 = labeled_module("M2") do
      def hello
        super
      end
    end

    foo = labeled_class("Foo") do
      include m1
      include m2

      alias orig_hello hello
      include fun
    end

    assert_equal('hello!', foo.new.hello, bug9236)
  end

  def test_prepend_each_classes
    m = labeled_module("M")
    c1 = labeled_class("C1") {prepend m}
    c2 = labeled_class("C2", c1) {prepend m}
    assert_equal([m, c2, m, c1], c2.ancestors[0, 4], "should be able to prepend each classes")
  end

  def test_prepend_no_duplication
    m = labeled_module("M")
    c = labeled_class("C") {prepend m; prepend m}
    assert_equal([m, c], c.ancestors[0, 2], "should never duplicate")
  end

  def test_prepend_in_superclass
    m = labeled_module("M")
    c1 = labeled_class("C1")
    c2 = labeled_class("C2", c1) {prepend m}
    c1.class_eval {prepend m}
    assert_equal([m, c2, m, c1], c2.ancestors[0, 4], "should accesisble prepended module in superclass")
  end

  def test_prepend_call_super
    assert_separately([], <<-'end;') #do
      bug10847 = '[ruby-core:68093] [Bug #10847]'
      module M; end
      Float.prepend M
      assert_nothing_raised(SystemStackError, bug10847) do
        0.3.numerator
      end
    end;
  end

  def test_prepend_module_with_no_args
    assert_raise(ArgumentError) { Module.new { prepend } }
  end

  def test_prepend_private_super
    wrapper = Module.new do
      def wrapped
        super + 1
      end
    end

    klass = Class.new do
      prepend wrapper

      def wrapped
        1
      end
      private :wrapped
    end

    assert_equal(2, klass.new.wrapped)
  end

  def test_class_variables
    m = Module.new
    m.class_variable_set(:@@foo, 1)
    m2 = Module.new
    m2.send(:include, m)
    m2.class_variable_set(:@@bar, 2)
    assert_equal([:@@foo], m.class_variables)
    assert_equal([:@@bar, :@@foo], m2.class_variables.sort)
    assert_equal([:@@bar, :@@foo], m2.class_variables(true).sort)
    assert_equal([:@@bar], m2.class_variables(false))
  end

  Bug6891 = '[ruby-core:47241]'

  def test_extend_module_with_protected_method
    list = []

    x = Class.new {
      @list = list

      extend Module.new {
        protected

        def inherited(klass)
          @list << "protected"
          super(klass)
        end
      }

      extend Module.new {
        def inherited(klass)
          @list << "public"
          super(klass)
        end
      }
    }

    assert_nothing_raised(NoMethodError, Bug6891) {Class.new(x)}
    assert_equal(['public', 'protected'], list)
  end

  def test_extend_module_with_protected_bmethod
    list = []

    x = Class.new {
      extend Module.new {
        protected

        define_method(:inherited) do |klass|
          list << "protected"
          super(klass)
        end
      }

      extend Module.new {
        define_method(:inherited) do |klass|
          list << "public"
          super(klass)
        end
      }
    }

    assert_nothing_raised(NoMethodError, Bug6891) {Class.new(x)}
    assert_equal(['public', 'protected'], list)
  end

  def test_extend_module_with_no_args
    assert_raise(ArgumentError) { Module.new { extend } }
  end

  def test_invalid_attr
    %W[
      foo?
      @foo
      @@foo
      $foo
      \u3042$
    ].each do |name|
      assert_raise_with_message(NameError, /#{Regexp.quote(quote(name))}/) do
        Module.new { attr_accessor name.to_sym }
      end
    end
  end

  private def quote(name)
    encoding = Encoding.default_internal || Encoding.default_external
    (name.encoding == encoding || name.ascii_only?) ? name : name.inspect
  end

  class AttrTest
    class << self
      attr_accessor :cattr
    end
    attr_accessor :iattr
    def ivar
      @ivar
    end
  end

  def test_uninitialized_instance_variable
    a = AttrTest.new
    assert_warning(/instance variable @ivar not initialized/) do
      assert_nil(a.ivar)
    end
    a.instance_variable_set(:@ivar, 42)
    assert_warning '' do
      assert_equal(42, a.ivar)
    end

    name = "@\u{5909 6570}"
    assert_warning(/instance variable #{name} not initialized/) do
      assert_nil(a.instance_eval(name))
    end
  end

  def test_uninitialized_attr
    a = AttrTest.new
    assert_warning '' do
      assert_nil(a.iattr)
    end
    a.iattr = 42
    assert_warning '' do
      assert_equal(42, a.iattr)
    end
  end

  def test_uninitialized_attr_class
    assert_warning '' do
      assert_nil(AttrTest.cattr)
    end
    AttrTest.cattr = 42
    assert_warning '' do
      assert_equal(42, AttrTest.cattr)
    end
  end

  def test_uninitialized_attr_non_object
    a = Class.new(Array) do
      attr_accessor :iattr
    end.new
    assert_warning '' do
      assert_nil(a.iattr)
    end
    a.iattr = 42
    assert_warning '' do
      assert_equal(42, a.iattr)
    end
  end

  def test_remove_const
    m = Module.new
    assert_raise(NameError){ m.instance_eval { remove_const(:__FOO__) } }
  end

  def test_private_top_methods
    assert_top_method_is_private(:include)
    assert_top_method_is_private(:public)
    assert_top_method_is_private(:private)
    assert_top_method_is_private(:define_method)
  end

  module PrivateConstantReopen
    PRIVATE_CONSTANT = true
    private_constant :PRIVATE_CONSTANT
  end

  def test_private_constant_reopen
    assert_raise(NameError) do
      eval <<-EOS, TOPLEVEL_BINDING
        module TestModule::PrivateConstantReopen::PRIVATE_CONSTANT
        end
      EOS
    end
    assert_raise(NameError) do
      eval <<-EOS, TOPLEVEL_BINDING
        class TestModule::PrivateConstantReopen::PRIVATE_CONSTANT
        end
      EOS
    end
  end

  def test_frozen_visibility
    bug11532 = '[ruby-core:70828] [Bug #11532]'

    c = Class.new {const_set(:A, 1)}.freeze
    assert_raise_with_message(RuntimeError, /frozen class/, bug11532) {
      c.class_eval {private_constant :A}
    }

    c = Class.new {const_set(:A, 1); private_constant :A}.freeze
    assert_raise_with_message(RuntimeError, /frozen class/, bug11532) {
      c.class_eval {public_constant :A}
    }

    c = Class.new {const_set(:A, 1)}.freeze
    assert_raise_with_message(RuntimeError, /frozen class/, bug11532) {
      c.class_eval {deprecate_constant :A}
    }
  end

  def test_singleton_class_ancestors
    feature8035 = '[ruby-core:53171]'
    obj = Object.new
    assert_equal [obj.singleton_class, Object], obj.singleton_class.ancestors.first(2), feature8035

    mod = Module.new
    obj.extend mod
    assert_equal [obj.singleton_class, mod, Object], obj.singleton_class.ancestors.first(3)

    obj = Object.new
    obj.singleton_class.send :prepend, mod
    assert_equal [mod, obj.singleton_class, Object], obj.singleton_class.ancestors.first(3)
  end

  def test_visibility_by_public_class_method
    bug8284 = '[ruby-core:54404] [Bug #8284]'
    assert_raise(NoMethodError) {Object.define_method}
    Module.new.public_class_method(:define_method)
    assert_raise(NoMethodError, bug8284) {Object.define_method}
  end

  def test_include_module_with_constants_does_not_invalidate_method_cache
    assert_in_out_err([], <<-RUBY, %w(123 456 true), [])
      A = 123

      class Foo
        def self.a
          A
        end
      end

      module M
        A = 456
      end

      puts Foo.a
      starting = RubyVM.stat[:global_method_state]

      Foo.send(:include, M)

      ending = RubyVM.stat[:global_method_state]
      puts Foo.a
      puts starting == ending
    RUBY
  end

  def test_return_value_of_define_method
    retvals = []
    Class.new.class_eval do
      retvals << define_method(:foo){}
      retvals << define_method(:bar, instance_method(:foo))
    end
    assert_equal :foo, retvals[0]
    assert_equal :bar, retvals[1]
  end

  def test_return_value_of_define_singleton_method
    retvals = []
    Class.new do
      retvals << define_singleton_method(:foo){}
      retvals << define_singleton_method(:bar, method(:foo))
    end
    assert_equal :foo, retvals[0]
    assert_equal :bar, retvals[1]
  end

  def test_prepend_gc
    assert_separately [], %{
      module Foo
      end
      class Object
        prepend Foo
      end
      GC.start     # make created T_ICLASS old (or remembered shady)
      class Object # add methods into T_ICLASS (need WB if it is old)
        def foo; end
        attr_reader :bar
      end
      1_000_000.times{''} # cause GC
    }
  end

  def test_inspect_segfault
    bug_10282 = '[ruby-core:65214] [Bug #10282]'
    assert_separately [], <<-RUBY
      module ShallowInspect
        def shallow_inspect
          "foo"
        end
      end

      module InspectIsShallow
        include ShallowInspect
        alias_method :inspect, :shallow_inspect
      end

      class A
      end

      A.prepend InspectIsShallow

      expect = "#<Method: A(ShallowInspect)#inspect(shallow_inspect)>"
      assert_equal expect, A.new.method(:inspect).inspect, "#{bug_10282}"
    RUBY
  end

  def test_define_method_with_unbound_method
    # Passing an UnboundMethod to define_method succeeds if it is from an ancestor
    assert_nothing_raised do
      cls = Class.new(String) do
        define_method('foo', String.instance_method(:to_s))
      end

      obj = cls.new('bar')
      assert_equal('bar', obj.foo)
    end

    # Passing an UnboundMethod to define_method fails if it is not from an ancestor
    assert_raise(TypeError) do
      Class.new do
        define_method('foo', String.instance_method(:to_s))
      end
    end
  end

  def test_redefinition_mismatch
    m = Module.new
    m.module_eval "A = 1"
    assert_raise_with_message(TypeError, /is not a module/) {
      m.module_eval "module A; end"
    }
    n = "M\u{1f5ff}"
    m.module_eval "#{n} = 42"
    assert_raise_with_message(TypeError, "#{n} is not a module") {
      m.module_eval "module #{n}; end"
    }

    assert_separately([], <<-"end;")
      Etc = (class C\u{1f5ff}; self; end).new
      assert_raise_with_message(TypeError, /C\u{1f5ff}/) {
        require 'etc'
      }
    end;
  end

  private

  def assert_top_method_is_private(method)
    assert_separately [], %{
      methods = singleton_class.private_instance_methods(false)
      assert_include(methods, :#{method}, ":#{method} should be private")

      assert_raise_with_message(NoMethodError, "private method `#{method}' called for main:Object") {
        self.#{method}
      }
    }
  end
end
