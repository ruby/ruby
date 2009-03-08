require 'test/unit'
require_relative 'envutil'

class TestObject < Test::Unit::TestCase
  def setup
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  def teardown
    $VERBOSE = @verbose
  end

  def test_dup
    assert_raise(TypeError) { 1.dup }
    assert_raise(TypeError) { true.dup }
    assert_raise(TypeError) { nil.dup }

    assert_raise(TypeError) do
      Object.new.instance_eval { initialize_copy(1) }
    end
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
    assert_raise(RuntimeError) { o.taint }

    o = Object.new
    o.taint
    o.freeze
    assert_raise(RuntimeError) { o.untaint }
  end

  def test_freeze_under_safe_4
    o = Object.new
    assert_raise(SecurityError) do
      Thread.new do
        $SAFE = 4
        o.freeze
      end.join
    end
  end

  def test_freeze_immediate
    assert_equal(false, 1.frozen?)
    1.freeze
    assert_equal(true, 1.frozen?)
    assert_equal(false, 2.frozen?)
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

  def test_instance_variable_get
    o = Object.new
    o.instance_eval { @foo = :foo }
    assert_equal(:foo, o.instance_variable_get(:@foo))
    assert_equal(nil, o.instance_variable_get(:@bar))
    assert_raise(NameError) { o.instance_variable_get(:foo) }
  end

  def test_instance_variable_set
    o = Object.new
    o.instance_variable_set(:@foo, :foo)
    assert_equal(:foo, o.instance_eval { @foo })
    assert_raise(NameError) { o.instance_variable_set(:foo, 1) }
  end

  def test_instance_variable_defined
    o = Object.new
    o.instance_eval { @foo = :foo }
    assert_equal(true, o.instance_variable_defined?(:@foo))
    assert_equal(false, o.instance_variable_defined?(:@bar))
    assert_raise(NameError) { o.instance_variable_defined?(:foo) }
  end

  def test_remove_instance_variable
    o = Object.new
    o.instance_eval { @foo = :foo }
    o.instance_eval { remove_instance_variable(:@foo) }
    assert_equal(false, o.instance_variable_defined?(:@foo))
  end

  def test_convert_type
    o = Object.new
    def o.to_s; 1; end
    assert_raise(TypeError) { String(o) }
  end

  def test_check_convert_type
    o = Object.new
    def o.to_a; 1; end
    assert_raise(TypeError) { Array(o) }
  end

  def test_to_integer
    o = Object.new
    def o.to_i; nil; end
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

  def test_add_method_under_safe4
    o = Object.new
    assert_raise(SecurityError) do
      Thread.new do
        $SAFE = 4
        def o.foo
        end
      end.join
    end
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
    assert_in_out_err([], <<-INPUT, [], /warning: redefining `object_id' may cause serious problem$/)
      $VERBOSE = false
      def (Object.new).object_id; end
    INPUT

    assert_in_out_err([], <<-INPUT, [], /warning: redefining `__send__' may cause serious problem$/)
      $VERBOSE = false
      def (Object.new).__send__; end
    INPUT
  end

  def test_remove_method
    assert_raise(SecurityError) do
      Thread.new do
        $SAFE = 4
        Object.instance_eval { remove_method(:foo) }
      end.join
    end

    assert_raise(SecurityError) do
      Thread.new do
        $SAFE = 4
        Class.instance_eval { remove_method(:foo) }
      end.join
    end

    c = Class.new
    c.freeze
    assert_raise(RuntimeError) do
      c.instance_eval { remove_method(:foo) }
    end

    %w(object_id __send__ initialize).each do |m|
      assert_in_out_err([], <<-INPUT, %w(:ok), /warning: removing `#{m}' may cause serious problem$/)
        $VERBOSE = false
        begin
          Class.new.instance_eval { remove_method(:#{m}) }
        rescue NameError
          p :ok
        end
      INPUT
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
  end

  def test_send_with_no_arguments
    assert_raise(ArgumentError) { 1.send }
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

  def test_instance_exec
    x = 1.instance_exec(42) {|a| self + a }
    assert_equal(43, x)

    x = "foo".instance_exec("bar") {|a| self + a }
    assert_equal("foobar", x)
  end

  def test_extend
    assert_raise(ArgumentError) do
      1.extend
    end
  end

  def test_untrusted
    obj = lambda {
      $SAFE = 4
      x = Object.new
      x.instance_eval { @foo = 1 }
      x
    }.call
    assert_equal(true, obj.untrusted?)
    assert_equal(true, obj.tainted?)

    x = Object.new
    assert_equal(false, x.untrusted?)
    assert_raise(SecurityError) do
      lambda {
        $SAFE = 4
        x.instance_eval { @foo = 1 }
      }.call
    end

    x = Object.new
    x.taint
    assert_raise(SecurityError) do
      lambda {
        $SAFE = 4
        x.instance_eval { @foo = 1 }
      }.call
    end

    x.untrust
    assert_equal(true, x.untrusted?)
    assert_nothing_raised do
      lambda {
        $SAFE = 4
        x.instance_eval { @foo = 1 }
      }.call
    end

    x.trust
    assert_equal(false, x.untrusted?)
    assert_raise(SecurityError) do
      lambda {
        $SAFE = 4
        x.instance_eval { @foo = 1 }
      }.call
    end

    a = Object.new
    a.untrust
    assert_equal(true, a.untrusted?)
    b = a.dup
    assert_equal(true, b.untrusted?)
    c = a.clone
    assert_equal(true, c.untrusted?)

    a = Object.new
    b = lambda {
      $SAFE = 4
      a.dup
    }.call
    assert_equal(true, b.untrusted?)

    a = Object.new
    b = lambda {
      $SAFE = 4
      a.clone
    }.call
    assert_equal(true, b.untrusted?)
  end

  def test_to_s
    x = Object.new
    x.taint
    x.untrust
    s = x.to_s
    assert_equal(true, s.untrusted?)
    assert_equal(true, s.tainted?)
  end
end
