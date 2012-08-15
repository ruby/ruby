require 'test/unit'

class TestRefinement < Test::Unit::TestCase
  class Foo
    def x
      return "Foo#x"
    end

    def y
      return "Foo#y"
    end

    def call_x
      return x
    end
  end

  module FooExt
    refine Foo do
      def x
        return "FooExt#x"
      end

      def y
        return "FooExt#y " + super
      end

      def z
        return "FooExt#z"
      end
    end
  end

  module FooExt2
    refine Foo do
      def x
        return "FooExt2#x"
      end

      def y
        return "FooExt2#y " + super
      end

      def z
        return "FooExt2#z"
      end
    end
  end

  class FooSub < Foo
    def x
      return "FooSub#x"
    end

    def y
      return "FooSub#y " + super
    end
  end

  class FooExtClient
    using FooExt

    def self.invoke_x_on(foo)
      return foo.x
    end

    def self.invoke_y_on(foo)
      return foo.y
    end

    def self.invoke_z_on(foo)
      return foo.z
    end

    def self.invoke_call_x_on(foo)
      return foo.call_x
    end
  end

  class FooExtClient2
    using FooExt
    using FooExt2

    def self.invoke_y_on(foo)
      return foo.y
    end
  end

  def test_override
    foo = Foo.new
    assert_equal("Foo#x", foo.x)
    assert_equal("FooExt#x", FooExtClient.invoke_x_on(foo))
    assert_equal("Foo#x", foo.x)
  end

  def test_super
    foo = Foo.new
    assert_equal("Foo#y", foo.y)
    assert_equal("FooExt#y Foo#y", FooExtClient.invoke_y_on(foo))
    assert_equal("Foo#y", foo.y)
  end

  def test_super_chain
    foo = Foo.new
    assert_equal("Foo#y", foo.y)
    assert_equal("FooExt2#y FooExt#y Foo#y", FooExtClient2.invoke_y_on(foo))
    assert_equal("Foo#y", foo.y)
  end

  def test_new_method
    foo = Foo.new
    assert_raise(NoMethodError) { foo.z }
    assert_equal("FooExt#z", FooExtClient.invoke_z_on(foo))
    assert_raise(NoMethodError) { foo.z }
  end

  def test_no_local_rebinding
    foo = Foo.new
    assert_equal("Foo#x", foo.call_x)
    assert_equal("Foo#x", FooExtClient.invoke_call_x_on(foo))
    assert_equal("Foo#x", foo.call_x)
  end

  def test_subclass_is_prior
    sub = FooSub.new
    assert_equal("FooSub#x", sub.x)
    assert_equal("FooSub#x", FooExtClient.invoke_x_on(sub))
    assert_equal("FooSub#x", sub.x)
  end

  def test_super_in_subclass
    sub = FooSub.new
    assert_equal("FooSub#y Foo#y", sub.y)
    # not "FooSub#y FooExt#y Foo#y"
    assert_equal("FooSub#y Foo#y", FooExtClient.invoke_y_on(sub))
    assert_equal("FooSub#y Foo#y", sub.y)
  end

  def test_new_method_on_subclass
    sub = FooSub.new
    assert_raise(NoMethodError) { sub.z }
    assert_equal("FooExt#z", FooExtClient.invoke_z_on(sub))
    assert_raise(NoMethodError) { sub.z }
  end

  def test_module_eval
    foo = Foo.new
    assert_equal("Foo#x", foo.x)
    assert_equal("FooExt#x", FooExt.module_eval { foo.x })
    assert_equal("Foo#x", foo.x)
  end

  def test_instance_eval
    foo = Foo.new
    ext_client = FooExtClient.new
    assert_equal("Foo#x", foo.x)
    assert_equal("FooExt#x", ext_client.instance_eval { foo.x })
    assert_equal("Foo#x", foo.x)
  end

  def test_override_builtin_method
    m = Module.new {
      refine Fixnum do
        def /(other) quo(other) end
      end
    }
    assert_equal(0, 1 / 2)
    assert_equal(Rational(1, 2), m.module_eval { 1 / 2 })
    assert_equal(0, 1 / 2)
  end

  def test_return_value_of_refine
    mod = nil
    result = nil
    m = Module.new {
      result = refine(Object) {
        mod = self
      }
    }
    assert_equal mod, result
  end

  def test_refine_same_class_twice
    result1 = nil
    result2 = nil
    result3 = nil
    m = Module.new {
      result1 = refine(Fixnum) {
        def foo; return "foo" end
      }
      result2 = refine(Fixnum) {
        def bar; return "bar" end
      }
      result3 = refine(String) {
        def baz; return "baz" end
      }
    }
    assert_equal("foo", m.module_eval { 1.foo })
    assert_equal("bar", m.module_eval { 1.bar })
    assert_equal(result1, result2)
    assert_not_equal(result1, result3)
  end

  def test_respond_to?
    m = Module.new {
      refine Fixnum do
        def foo; "foo"; end
      end
    }
    assert_equal(false, 1.respond_to?(:foo))
    assert_equal(true, m.module_eval { 1.respond_to?(:foo) })
    assert_equal(false, 1.respond_to?(:foo))
  end

  def test_builtin_method_no_local_rebinding
    m = Module.new {
      refine String do
        def <=>(other) return 0 end
      end
    }
    assert_equal(false, m.module_eval { "1" >= "2" })

    m2 = Module.new {
      refine Array do
        def each
          super do |i|
            yield 2 * i
          end
        end
      end
    }
    a = [1, 2, 3]
    assert_equal(1, m2.module_eval { a.min })
  end

  def test_module_inclusion
    m1 = Module.new {
      def foo
        "m1#foo"
      end

      def bar
        "m1#bar"
      end
    }
    m2 = Module.new {
      def bar
        "m2#bar"
      end

      def baz
        "m2#baz"
      end
    }
    m3 = Module.new {
      def baz
        "m3#baz"
      end
    }
    include_proc = Proc.new {
      include m3, m2
    }
    m = Module.new {
      refine String do
        include m1
        module_eval(&include_proc)

        def call_foo
          foo
        end

        def call_bar
          bar
        end

        def call_baz
          baz
        end
      end

      def self.call_foo(s)
        s.foo
      end

      def self.call_bar(s)
        s.bar
      end

      def self.call_baz(s)
        s.baz
      end
    }
    assert_equal("m1#foo", m.module_eval { "abc".foo })
    assert_equal("m2#bar", m.module_eval { "abc".bar })
    assert_equal("m3#baz", m.module_eval { "abc".baz })
    assert_equal("m1#foo", m.module_eval { "abc".call_foo })
    assert_equal("m2#bar", m.module_eval { "abc".call_bar })
    assert_equal("m3#baz", m.module_eval { "abc".call_baz })
    assert_equal("m1#foo", m.call_foo("abc"))
    assert_equal("m2#bar", m.call_bar("abc"))
    assert_equal("m3#baz", m.call_baz("abc"))
  end

  def test_refine_prepended_class
    m1 = Module.new {
      def foo
        super << :m1
      end
    }
    c = Class.new {
      prepend m1

      def foo
        [:c]
      end
    }
    m2 = Module.new {
      refine c do
        def foo
          super << :m2
        end
      end
    }
    obj = c.new
    assert_equal([:c, :m1, :m2], m2.module_eval { obj.foo })
  end
end

