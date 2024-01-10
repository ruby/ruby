# frozen_string_literal: false
require 'test/unit'

class TestDefined < Test::Unit::TestCase
  class Foo
    def foo
      p :foo
    end
    protected :foo
    def bar(f)
      yield(defined?(self.foo))
      yield(defined?(f.foo))
    end
    def baz(f)
    end
    attr_accessor :attr
    def attrasgn_test
      yield(defined?(self.attr = 1))
    end
  end

  def defined_test
    return !defined?(yield)
  end

  def test_defined_global_variable
    $x = nil

    assert(defined?($x))		# global variable
    assert_equal('global-variable', defined?($x))# returns description
  end

  def test_defined_local_variable
    assert_nil(defined?(foo))		# undefined
    foo=5
    assert(defined?(foo))		# local variable
  end

  def test_defined_constant
    assert(defined?(Array))		# constant
    assert(defined?(::Array))		# toplevel constant
    assert(defined?(File::Constants))	# nested constant
  end

  def test_defined_public_method
    assert(defined?(Object.new))	# method
    assert(defined?(Object::new))	# method
  end

  def test_defined_private_method
    assert(!defined?(Object.print))	# private method
  end

  def test_defined_operator
    assert(defined?(1 == 2))		# operator expression
  end

  def test_defined_protected_method
    f = Foo.new
    assert_nil(defined?(f.foo))         # protected method
    f.bar(f) { |v| assert(v) }
    f.bar(Class.new(Foo).new) { |v| assert(v, "inherited protected method") }
  end

  def test_defined_undefined_method
    f = Foo.new
    assert_nil(defined?(f.quux))        # undefined method
  end

  def test_defined_undefined_argument
    f = Foo.new
    assert_nil(defined?(f.baz(x)))      # undefined argument
    x = 0
    assert(defined?(f.baz(x)))
    assert_nil(defined?(f.quux(x)))
    assert(defined?(print(x)))
    assert_nil(defined?(quux(x)))
  end

  def test_defined_attrasgn
    f = Foo.new
    assert(defined?(f.attr = 1))
    f.attrasgn_test { |v| assert(v) }
  end

  def test_defined_undef
    x = Object.new
    def x.foo; end
    assert(defined?(x.foo))
    x.instance_eval {undef :foo}
    assert(!defined?(x.foo), "undefed method should not be defined?")
  end

  def test_defined_yield
    assert(defined_test)		# not iterator
    assert(!defined_test{})	        # called as iterator
  end

  def test_defined_matchdata
    /a/ =~ ''
    assert_equal nil, defined?($&)
    assert_equal nil, defined?($`)
    assert_equal nil, defined?($')
    assert_equal nil, defined?($+)
    assert_equal nil, defined?($1)
    assert_equal nil, defined?($2)
    /a/ =~ 'a'
    assert_equal 'global-variable', defined?($&)
    assert_equal 'global-variable', defined?($`)
    assert_equal 'global-variable', defined?($') # '
    assert_equal nil, defined?($+)
    assert_equal nil, defined?($1)
    assert_equal nil, defined?($2)
    /(a)/ =~ 'a'
    assert_equal 'global-variable', defined?($&)
    assert_equal 'global-variable', defined?($`)
    assert_equal 'global-variable', defined?($') # '
    assert_equal 'global-variable', defined?($+)
    assert_equal 'global-variable', defined?($1)
    assert_equal nil, defined?($2)
    /(a)b/ =~ 'ab'
    assert_equal 'global-variable', defined?($&)
    assert_equal 'global-variable', defined?($`)
    assert_equal 'global-variable', defined?($') # '
    assert_equal 'global-variable', defined?($+)
    assert_equal 'global-variable', defined?($1)
    assert_equal nil, defined?($2)
  end

  def test_defined_assignment
    assert_equal("assignment", defined?(a = 1))
    assert_equal("assignment", defined?(a += 1))
    assert_equal("assignment", defined?(a &&= 1))
    assert_equal("assignment", eval('defined?(A = 1)'))
    assert_equal("assignment", eval('defined?(A += 1)'))
    assert_equal("assignment", eval('defined?(A &&= 1)'))
    assert_equal("assignment", eval('defined?(A::B = 1)'))
    assert_equal("assignment", eval('defined?(A::B += 1)'))
    assert_equal("assignment", eval('defined?(A::B &&= 1)'))
  end

  def test_defined_literal
    assert_equal("nil", defined?(nil))
    assert_equal("true", defined?(true))
    assert_equal("false", defined?(false))
    assert_equal("expression", defined?(1))
  end

  def test_defined_method
    self_ = self
    assert_equal("method", defined?(test_defined_method))
    assert_equal("method", defined?(self.test_defined_method))
    assert_equal("method", defined?(self_.test_defined_method))

    assert_equal(nil, defined?(1.test_defined_method))
    assert_equal("method", defined?(1.to_i))
    assert_equal(nil, defined?(1.to_i.test_defined_method))
    assert_equal(nil, defined?(1.test_defined_method.to_i))

    assert_equal("method", defined?("x".reverse))
    assert_equal("method", defined?("x".reverse(1)))
    assert_equal("method", defined?("x".reverse.reverse))
    assert_equal(nil, defined?("x".reverse(1).reverse))

    assert_equal("method", defined?(1.to_i(10)))
    assert_equal("method", defined?(1.to_i("x")))
    assert_equal(nil, defined?(1.to_i("x").undefined))
    assert_equal(nil, defined?(1.to_i(undefined).to_i))
    assert_equal(nil, defined?(1.to_i("x").undefined.to_i))
    assert_equal(nil, defined?(1.to_i(undefined).to_i.to_i))
  end

  def test_defined_method_single_call
    times_called = 0
    define_singleton_method(:t) do
      times_called += 1
      self
    end
    assert_equal("method", defined?(t))
    assert_equal(0, times_called)

    assert_equal("method", defined?(t.t))
    assert_equal(1, times_called)

    times_called = 0
    assert_equal("method", defined?(t.t.t))
    assert_equal(2, times_called)

    times_called = 0
    assert_equal("method", defined?(t.t.t.t))
    assert_equal(3, times_called)

    times_called = 0
    assert_equal("method", defined?(t.t.t.t.t))
    assert_equal(4, times_called)
  end

  def test_defined_empty_paren_expr
    bug8224 = '[ruby-core:54024] [Bug #8224]'
    (1..3).each do |level|
      expr = "("*level+")"*level
      assert_equal("nil", eval("defined? #{expr}"), "#{bug8224} defined? #{expr}")
      assert_equal("nil", eval("defined?(#{expr})"), "#{bug8224} defined?(#{expr})")
    end
  end

  def test_defined_empty_paren_arg
    assert_nil(defined?(p () + 1))
  end

  def test_defined_impl_specific
    feature7035 = '[ruby-core:47558]' # not spec
    assert_predicate(defined?(Foo), :frozen?, feature7035)
    assert_same(defined?(Foo), defined?(Array), feature7035)
  end

  class TestAutoloadedSuperclass
    autoload :A, "a"
  end

  class TestAutoloadedSubclass < TestAutoloadedSuperclass
    def a?
      defined?(A)
    end
  end

  def test_autoloaded_subclass
    bug = "[ruby-core:35509]"

    x = TestAutoloadedSuperclass.new
    class << x
      def a?; defined?(A); end
    end
    assert_equal("constant", x.a?, bug)

    assert_equal("constant", TestAutoloadedSubclass.new.a?, bug)
  end

  class TestAutoloadedNoload
    autoload :A, "a"
    def a?
      defined?(A)
    end
    def b?
      defined?(A::B)
    end
  end

  def test_autoloaded_noload
    loaded = $".dup
    $".clear
    loadpath = $:.dup
    $:.clear
    x = TestAutoloadedNoload.new
    assert_equal("constant", x.a?)
    assert_nil(x.b?)
    assert_equal([], $")
  ensure
    $".replace(loaded)
    $:.replace(loadpath)
  end

  def test_exception
    bug5786 = '[ruby-dev:45021]'
    assert_nil(defined?(raise("[Bug#5786]")::A), bug5786)
  end

  def test_define_method
    bug6644 = '[ruby-core:45831]'
    a = Class.new do
      def self.def_f!;
        singleton_class.send(:define_method, :f) { defined? super }
      end
    end
    aa = Class.new(a)
    a.def_f!
    assert_nil(a.f)
    assert_nil(aa.f)
    aa.def_f!
    assert_equal("super", aa.f, bug6644)
    assert_nil(a.f, bug6644)
  end

  def test_super_in_included_method
    c0 = Class.new do
      def m
      end
    end
    m1 = Module.new do
      def m
        defined?(super)
      end
    end
    c = Class.new(c0) do include m1
      def m
        super
      end
    end
    assert_equal("super", c.new.m)
  end

  def test_super_in_block
    bug8367 = '[ruby-core:54769] [Bug #8367]'
    c = Class.new do
      def x; end
    end

    m = Module.new do
      def b; yield; end
      def x; b {return defined?(super)}; end
    end

    o = c.new
    o.extend(m)
    assert_equal("super", o.x, bug8367)
  end

  def test_super_in_basic_object
    BasicObject.class_eval do
      def a
        defined?(super)
      end
    end

    assert_nil(a)
  ensure
    BasicObject.class_eval do
      undef_method :a if defined?(a)
    end
  end

  def test_super_toplevel
    assert_separately([], "assert_nil(defined?(super))")
  end

  def test_respond_to
    obj = "#{self.class.name}##{__method__}"
    class << obj
      def respond_to?(mid)
        true
      end
    end
    assert_warn(/deprecated method signature.*\n.*respond_to\? is defined here/) do
      Warning[:deprecated] = true
      defined?(obj.foo)
    end
    assert_warn('') do
      Warning[:deprecated] = false
      defined?(obj.foo)
    end
  end

  class ExampleRespondToMissing
    attr_reader :called

    def initialize
      @called = false
    end

    def respond_to_missing? *args
      @called = true
      false
    end

    def existing_method
    end

    def func_defined_existing_func
      defined?(existing_method())
    end

    def func_defined_non_existing_func
      defined?(non_existing_method())
    end
  end

  def test_method_by_respond_to_missing
    bug_11211 = '[Bug #11211]'
    obj = ExampleRespondToMissing.new
    assert_equal("method", defined?(obj.existing_method), bug_11211)
    assert_equal(false, obj.called, bug_11211)
    assert_equal(nil, defined?(obj.non_existing_method), bug_11211)
    assert_equal(true, obj.called, bug_11211)

    bug_11212 = '[Bug #11212]'
    obj = ExampleRespondToMissing.new
    assert_equal("method", obj.func_defined_existing_func, bug_11212)
    assert_equal(false, obj.called, bug_11212)
    assert_equal(nil, obj.func_defined_non_existing_func, bug_11212)
    assert_equal(true, obj.called, bug_11212)
  end

  def test_top_level_constant_not_defined
    assert_nil(defined?(TestDefined::Object))
  end

  class RefinedClass
  end

  module RefiningModule
    refine RefinedClass do
      def pub
      end

      private

      def priv
      end
    end

    def self.call_without_using(x = RefinedClass.new)
      defined?(x.pub)
    end

    def self.vcall_without_using(x = RefinedClass.new)
      x.instance_eval {defined?(priv)}
    end

    using self

    def self.call_with_using(x = RefinedClass.new)
      defined?(x.pub)
    end

    def self.vcall_with_using(x = RefinedClass.new)
      x.instance_eval {defined?(priv)}
    end
  end

  def test_defined_refined_call_without_using
    assert(!RefiningModule.call_without_using, "refined public method without using")
  end

  def test_defined_refined_vcall_without_using
    assert(!RefiningModule.vcall_without_using, "refined private method without using")
  end

  def test_defined_refined_call_with_using
    assert(RefiningModule.call_with_using, "refined public method with using")
  end

  def test_defined_refined_vcall_with_using
    assert(RefiningModule.vcall_with_using, "refined private method with using")
  end
end
