# frozen_string_literal: false
require 'test/unit'

class TestRefinement < Test::Unit::TestCase
  module Sandbox
    BINDING = binding
  end

  class Foo
    def x
      return "Foo#x"
    end

    def y
      return "Foo#y"
    end

    def a
      return "Foo#a"
    end

    def b
      return "Foo#b"
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

      def a
        return "FooExt#a"
      end

      private def b
        return "FooExt#b"
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
    using TestRefinement::FooExt

    begin
      def self.map_x_on(foo)
        [foo].map(&:x)[0]
      end

      def self.invoke_x_on(foo)
        return foo.x
      end

      def self.invoke_y_on(foo)
        return foo.y
      end

      def self.invoke_z_on(foo)
        return foo.z
      end

      def self.send_z_on(foo)
        return foo.send(:z)
      end

      def self.send_b_on(foo)
        return foo.send(:b)
      end

      def self.public_send_z_on(foo)
        return foo.public_send(:z)
      end

      def self.public_send_b_on(foo)
        return foo.public_send(:b)
      end

      def self.method_z(foo)
        return foo.method(:z)
      end

      def self.instance_method_z(foo)
        return foo.class.instance_method(:z)
      end

      def self.invoke_call_x_on(foo)
        return foo.call_x
      end

      def self.return_proc(&block)
        block
      end
    end
  end

  class TestRefinement::FooExtClient2
    using TestRefinement::FooExt
    using TestRefinement::FooExt2

    begin
      def self.invoke_y_on(foo)
        return foo.y
      end

      def self.invoke_a_on(foo)
        return foo.a
      end
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

  def test_super_not_chained
    foo = Foo.new
    assert_equal("Foo#y", foo.y)
    assert_equal("FooExt2#y Foo#y", FooExtClient2.invoke_y_on(foo))
    assert_equal("Foo#y", foo.y)
  end

  def test_using_same_class_refinements
    foo = Foo.new
    assert_equal("Foo#a", foo.a)
    assert_equal("FooExt#a", FooExtClient2.invoke_a_on(foo))
    assert_equal("Foo#a", foo.a)
  end

  def test_new_method
    foo = Foo.new
    assert_raise(NoMethodError) { foo.z }
    assert_equal("FooExt#z", FooExtClient.invoke_z_on(foo))
    assert_raise(NoMethodError) { foo.z }
  end

  module RespondTo
    class Super
      def foo
      end
    end

    class Sub < Super
    end

    module M
      refine Sub do
        def foo
        end
      end
    end
  end

  def test_send_should_use_refinements
    foo = Foo.new
    assert_raise(NoMethodError) { foo.send(:z) }
    assert_equal("FooExt#z", FooExtClient.send_z_on(foo))
    assert_equal("FooExt#b", FooExtClient.send_b_on(foo))
    assert_raise(NoMethodError) { foo.send(:z) }

    assert_equal(true, RespondTo::Sub.new.respond_to?(:foo))
  end

  def test_public_send_should_use_refinements
    foo = Foo.new
    assert_raise(NoMethodError) { foo.public_send(:z) }
    assert_equal("FooExt#z", FooExtClient.public_send_z_on(foo))
    assert_equal("Foo#b", foo.public_send(:b))
    assert_raise(NoMethodError) { FooExtClient.public_send_b_on(foo) }
  end

  module MethodIntegerPowEx
    refine Integer do
      def pow(*)
        :refine_pow
      end
    end
  end
  def test_method_should_use_refinements
    skip if Minitest::Unit.current_repeat_count > 0

    foo = Foo.new
    assert_raise(NameError) { foo.method(:z) }
    assert_equal("FooExt#z", FooExtClient.method_z(foo).call)
    assert_raise(NameError) { foo.method(:z) }
    assert_equal(8, eval(<<~EOS, Sandbox::BINDING))
      meth = 2.method(:pow)
      using MethodIntegerPowEx
      meth.call(3)
    EOS
    assert_equal(:refine_pow, eval_using(MethodIntegerPowEx, "2.pow(3)"))
    assert_equal(:refine_pow, eval_using(MethodIntegerPowEx, "2.method(:pow).(3)"))
  end

  module InstanceMethodIntegerPowEx
    refine Integer do
      def abs
        :refine_abs
      end
    end
  end
  def test_instance_method_should_use_refinements
    skip if Minitest::Unit.current_repeat_count > 0

    foo = Foo.new
    assert_raise(NameError) { Foo.instance_method(:z) }
    assert_equal("FooExt#z", FooExtClient.instance_method_z(foo).bind(foo).call)
    assert_raise(NameError) { Foo.instance_method(:z) }
    assert_equal(4, eval(<<~EOS, Sandbox::BINDING))
      meth = Integer.instance_method(:abs)
      using InstanceMethodIntegerPowEx
      meth.bind(-4).call
    EOS
    assert_equal(:refine_abs, eval_using(InstanceMethodIntegerPowEx, "Integer.instance_method(:abs).bind(-4).call"))
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
    assert_equal("Foo#x", FooExt.module_eval { foo.x })
    assert_equal("Foo#x", FooExt.module_eval("foo.x"))
    assert_equal("Foo#x", foo.x)
  end

  def test_instance_eval_without_refinement
    foo = Foo.new
    ext_client = FooExtClient.new
    assert_equal("Foo#x", foo.x)
    assert_equal("Foo#x", ext_client.instance_eval { foo.x })
    assert_equal("Foo#x", foo.x)
  end

  module IntegerSlashExt
    refine Integer do
      def /(other) quo(other) end
    end
  end

  def test_override_builtin_method
    assert_equal(0, 1 / 2)
    assert_equal(Rational(1, 2), eval_using(IntegerSlashExt, "1 / 2"))
    assert_equal(0, 1 / 2)
  end

  module IntegerPlusExt
    refine Integer do
      def self.method_added(*args); end
      def +(other) "overridden" end
    end
  end

  def test_override_builtin_method_with_method_added
    assert_equal(3, 1 + 2)
    assert_equal("overridden", eval_using(IntegerPlusExt, "1 + 2"))
    assert_equal(3, 1 + 2)
  end

  def test_return_value_of_refine
    mod = nil
    result = nil
    Module.new {
      result = refine(Object) {
        mod = self
      }
    }
    assert_equal mod, result
  end

  module RefineSameClass
    REFINEMENT1 = refine(Integer) {
      def foo; return "foo" end
    }
    REFINEMENT2 = refine(Integer) {
      def bar; return "bar" end
    }
    REFINEMENT3 = refine(String) {
      def baz; return "baz" end
    }
  end

  def test_refine_same_class_twice
    assert_equal("foo", eval_using(RefineSameClass, "1.foo"))
    assert_equal("bar", eval_using(RefineSameClass, "1.bar"))
    assert_equal(RefineSameClass::REFINEMENT1, RefineSameClass::REFINEMENT2)
    assert_not_equal(RefineSameClass::REFINEMENT1, RefineSameClass::REFINEMENT3)
  end

  module IntegerFooExt
    refine Integer do
      def foo; "foo"; end
    end
  end

  def test_respond_to_should_use_refinements
    assert_equal(false, 1.respond_to?(:foo))
    assert_equal(true, eval_using(IntegerFooExt, "1.respond_to?(:foo)"))
  end

  module StringCmpExt
    refine String do
      def <=>(other) return 0 end
    end
  end

  module ArrayEachExt
    refine Array do
      def each
        super do |i|
          yield 2 * i
        end
      end
    end
  end

  def test_builtin_method_no_local_rebinding
    assert_equal(false, eval_using(StringCmpExt, '"1" >= "2"'))
    assert_equal(1, eval_using(ArrayEachExt, "[1, 2, 3].min"))
  end

  module RefinePrependedClass
    module M1
      def foo
        super << :m1
      end
    end

    class C
      prepend M1

      def foo
        [:c]
      end
    end

    module M2
      refine C do
        def foo
          super << :m2
        end
      end
    end
  end

  def test_refine_prepended_class
    x = eval_using(RefinePrependedClass::M2,
                   "TestRefinement::RefinePrependedClass::C.new.foo")
    assert_equal([:c, :m1, :m2], x)
  end

  module RefineModule
    module M
      def foo
        "M#foo"
      end

      def bar
        "M#bar"
      end

      def baz
        "M#baz"
      end
    end

    class C
      include M

      def baz
        "#{super} C#baz"
      end
    end

    module M2
      refine M do
        def foo
          "M@M2#foo"
        end

        def bar
          "#{super} M@M2#bar"
        end

        def baz
          "#{super} M@M2#baz"
        end
      end
    end

    using M2

    def self.call_foo
      C.new.foo
    end

    def self.call_bar
      C.new.bar
    end

    def self.call_baz
      C.new.baz
    end
  end

  def test_refine_module
    assert_equal("M@M2#foo", RefineModule.call_foo)
    assert_equal("M#bar M@M2#bar", RefineModule.call_bar)
    assert_equal("M#baz C#baz", RefineModule.call_baz)
  end

  module RefineIncludeActivatedSuper
    class C
      def foo
        ["C"]
      end
    end

    module M; end

    refinement = Module.new do
      R = refine C do
        def foo
          ["R"] + super
        end

        include M
      end
    end

    using refinement
    M.define_method(:foo){["M"] + super()}

    def self.foo
      C.new.foo
    end
  end

  def test_refine_include_activated_super
    assert_equal(["R", "M", "C"], RefineIncludeActivatedSuper.foo)
  end

  def test_refine_neither_class_nor_module
    assert_raise(TypeError) do
      Module.new {
        refine Object.new do
        end
      }
    end
    assert_raise(TypeError) do
      Module.new {
        refine 123 do
        end
      }
    end
    assert_raise(TypeError) do
      Module.new {
        refine "foo" do
        end
      }
    end
  end

  def test_refine_in_class
    assert_raise(NoMethodError) do
      Class.new {
        refine Integer do
          def foo
            "c"
          end
        end
      }
    end
  end

  def test_main_using
    assert_in_out_err([], <<-INPUT, %w(:C :M), [])
      class C
        def foo
          :C
        end
      end

      module M
        refine C do
          def foo
            :M
          end
        end
      end

      c = C.new
      p c.foo
      using M
      p c.foo
    INPUT
  end

  def test_main_using_is_private
    assert_raise(NoMethodError) do
      eval("recv = self; recv.using Module.new", Sandbox::BINDING)
    end
  end

  def test_no_kernel_using
    assert_raise(NoMethodError) do
      using Module.new
    end
  end

  class UsingClass
  end

  def test_module_using_class
    assert_raise(TypeError) do
      eval("using TestRefinement::UsingClass", Sandbox::BINDING)
    end
  end

  def test_refine_without_block
    c1 = Class.new
    assert_raise_with_message(ArgumentError, "no block given") {
      Module.new do
        refine c1
      end
    }
  end

  module Inspect
    module M
      Integer = refine(Integer) {}
    end
  end

  def test_inspect
    assert_equal("#<refinement:Integer@TestRefinement::Inspect::M>",
                 Inspect::M::Integer.inspect)
  end

  def test_using_method_cache
    assert_in_out_err([], <<-INPUT, %w(:M1 :M2), [])
      class C
        def foo
          "original"
        end
      end

      module M1
        refine C do
          def foo
            :M1
          end
        end
      end

      module M2
        refine C do
          def foo
            :M2
          end
        end
      end

      c = C.new
      using M1
      p c.foo
      using M2
      p c.foo
    INPUT
  end

  module RedefineRefinedMethod
    class C
      def foo
        "original"
      end
    end

    module M
      refine C do
        def foo
          "refined"
        end
      end
    end

    class C
      EnvUtil.suppress_warning do
        def foo
          "redefined"
        end
      end
    end
  end

  def test_redefine_refined_method
    x = eval_using(RedefineRefinedMethod::M,
                   "TestRefinement::RedefineRefinedMethod::C.new.foo")
    assert_equal("refined", x)
  end

  module StringExt
    refine String do
      def foo
        "foo"
      end
    end
  end

  module RefineScoping
    refine String do
      def foo
        "foo"
      end

      def RefineScoping.call_in_refine_block
        "".foo
      end
    end

    def self.call_outside_refine_block
      "".foo
    end
  end

  def test_refine_scoping
    assert_equal("foo", RefineScoping.call_in_refine_block)
    assert_raise(NoMethodError) do
      RefineScoping.call_outside_refine_block
    end
  end

  module StringRecursiveLength
    refine String do
      def recursive_length
        if empty?
          0
        else
          self[1..-1].recursive_length + 1
        end
      end
    end
  end

  def test_refine_recursion
    x = eval_using(StringRecursiveLength, "'foo'.recursive_length")
    assert_equal(3, x)
  end

  module ToJSON
    refine Integer do
      def to_json; to_s; end
    end

    refine Array do
      def to_json; "[" + map { |i| i.to_json }.join(",") + "]" end
    end

    refine Hash do
      def to_json; "{" + map { |k, v| k.to_s.dump + ":" + v.to_json }.join(",") + "}" end
    end
  end

  def test_refine_mutual_recursion
    x = eval_using(ToJSON, "[{1=>2}, {3=>4}].to_json")
    assert_equal('[{"1":2},{"3":4}]', x)
  end

  def test_refine_with_proc
    assert_raise(ArgumentError) do
      Module.new {
        refine(String, &Proc.new {})
      }
    end
  end

  def test_using_in_module
    assert_raise(RuntimeError) do
      eval(<<-EOF, Sandbox::BINDING)
        $main = self
        module M
        end
        module M2
          $main.send(:using, M)
        end
      EOF
    end
  end

  def test_using_in_method
    assert_raise(RuntimeError) do
      eval(<<-EOF, Sandbox::BINDING)
        $main = self
        module M
        end
        class C
          def call_using_in_method
            $main.send(:using, M)
          end
        end
        C.new.call_using_in_method
      EOF
    end
  end

  module IncludeIntoRefinement
    class C
      def bar
        return "C#bar"
      end

      def baz
        return "C#baz"
      end
    end

    module Mixin
      def foo
        return "Mixin#foo"
      end

      def bar
        return super << " Mixin#bar"
      end

      def baz
        return super << " Mixin#baz"
      end
    end

    module M
      refine C do
        include Mixin

        def baz
          return super << " M#baz"
        end
      end
    end
  end

  eval <<-EOF, Sandbox::BINDING
    using TestRefinement::IncludeIntoRefinement::M

    module TestRefinement::IncludeIntoRefinement::User
      def self.invoke_foo_on(x)
        x.foo
      end

      def self.invoke_bar_on(x)
        x.bar
      end

      def self.invoke_baz_on(x)
        x.baz
      end
    end
  EOF

  def test_include_into_refinement
    x = IncludeIntoRefinement::C.new
    assert_equal("Mixin#foo", IncludeIntoRefinement::User.invoke_foo_on(x))
    assert_equal("C#bar Mixin#bar",
                 IncludeIntoRefinement::User.invoke_bar_on(x))
    assert_equal("C#baz Mixin#baz M#baz",
                 IncludeIntoRefinement::User.invoke_baz_on(x))
  end

  module PrependIntoRefinement
    class C
      def bar
        return "C#bar"
      end

      def baz
        return "C#baz"
      end
    end

    module Mixin
      def foo
        return "Mixin#foo"
      end

      def bar
        return super << " Mixin#bar"
      end

      def baz
        return super << " Mixin#baz"
      end
    end

    module M
      refine C do
        prepend Mixin

        def baz
          return super << " M#baz"
        end
      end
    end
  end

  eval <<-EOF, Sandbox::BINDING
    using TestRefinement::PrependIntoRefinement::M

    module TestRefinement::PrependIntoRefinement::User
      def self.invoke_foo_on(x)
        x.foo
      end

      def self.invoke_bar_on(x)
        x.bar
      end

      def self.invoke_baz_on(x)
        x.baz
      end
    end
  EOF

  def test_prepend_into_refinement
    x = PrependIntoRefinement::C.new
    assert_equal("Mixin#foo", PrependIntoRefinement::User.invoke_foo_on(x))
    assert_equal("C#bar Mixin#bar",
                 PrependIntoRefinement::User.invoke_bar_on(x))
    assert_equal("C#baz M#baz Mixin#baz",
                 PrependIntoRefinement::User.invoke_baz_on(x))
  end

  PrependAfterRefine_CODE = <<-EOC
  module PrependAfterRefine
    class C
      def foo
        "original"
      end
    end

    module M
      refine C do
        def foo
          "refined"
        end

        def bar
          "refined"
        end
      end
    end

    module Mixin
      def foo
        "mixin"
      end

      def bar
        "mixin"
      end
    end

    class C
      prepend Mixin
    end
  end
  EOC
  eval PrependAfterRefine_CODE

  def test_prepend_after_refine_wb_miss
    if /\A(arm|mips)/ =~ RUBY_PLATFORM
      skip "too slow cpu"
    end
    assert_normal_exit %Q{
      GC.stress = true
      10.times{
        #{PrependAfterRefine_CODE}
        undef PrependAfterRefine
      }
    }, timeout: 60
  end

  def test_prepend_after_refine
    x = eval_using(PrependAfterRefine::M,
                   "TestRefinement::PrependAfterRefine::C.new.foo")
    assert_equal("refined", x)
    assert_equal("mixin", TestRefinement::PrependAfterRefine::C.new.foo)
    y = eval_using(PrependAfterRefine::M,
                   "TestRefinement::PrependAfterRefine::C.new.bar")
    assert_equal("refined", y)
    assert_equal("mixin", TestRefinement::PrependAfterRefine::C.new.bar)
  end

  module SuperInBlock
    class C
      def foo(*args)
        [:foo, *args]
      end
    end

    module R
      refine C do
        def foo(*args)
          tap do
            return super(:ref, *args)
          end
        end
      end
    end
  end

  def test_super_in_block
    bug7925 = '[ruby-core:52750] [Bug #7925]'
    x = eval_using(SuperInBlock::R,
                   "TestRefinement:: SuperInBlock::C.new.foo(#{bug7925.dump})")
    assert_equal([:foo, :ref, bug7925], x, bug7925)
  end

  module ModuleUsing
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

    def self.send_z_on(foo)
      return foo.send(:z)
    end

    def self.public_send_z_on(foo)
      return foo.public_send(:z)
    end

    def self.method_z(foo)
      return foo.method(:z)
    end

    def self.invoke_call_x_on(foo)
      return foo.call_x
    end
  end

  def test_module_using
    foo = Foo.new
    assert_equal("Foo#x", foo.x)
    assert_equal("Foo#y", foo.y)
    assert_raise(NoMethodError) { foo.z }
    assert_equal("FooExt#x", ModuleUsing.invoke_x_on(foo))
    assert_equal("FooExt#y Foo#y", ModuleUsing.invoke_y_on(foo))
    assert_equal("FooExt#z", ModuleUsing.invoke_z_on(foo))
    assert_equal("Foo#x", foo.x)
    assert_equal("Foo#y", foo.y)
    assert_raise(NoMethodError) { foo.z }
  end

  def test_module_using_in_method
    assert_raise(RuntimeError) do
      Module.new.send(:using, FooExt)
    end
  end

  def test_module_using_invalid_self
    assert_raise(RuntimeError) do
      eval <<-EOF, Sandbox::BINDING
        module TestRefinement::TestModuleUsingInvalidSelf
          Module.new.send(:using, TestRefinement::FooExt)
        end
      EOF
    end
  end

  class Bar
  end

  module BarExt
    refine Bar do
      def x
        return "BarExt#x"
      end
    end
  end

  module FooBarExt
    include FooExt
    include BarExt
  end

  module FooBarExtClient
    using FooBarExt

    def self.invoke_x_on(foo)
      return foo.x
    end
  end

  def test_module_inclusion
    foo = Foo.new
    assert_equal("FooExt#x", FooBarExtClient.invoke_x_on(foo))
    bar = Bar.new
    assert_equal("BarExt#x", FooBarExtClient.invoke_x_on(bar))
  end

  module FooFoo2Ext
    include FooExt
    include FooExt2
  end

  module FooFoo2ExtClient
    using FooFoo2Ext

    def self.invoke_x_on(foo)
      return foo.x
    end

    def self.invoke_y_on(foo)
      return foo.y
    end
  end

  def test_module_inclusion2
    foo = Foo.new
    assert_equal("FooExt2#x", FooFoo2ExtClient.invoke_x_on(foo))
    assert_equal("FooExt2#y Foo#y", FooFoo2ExtClient.invoke_y_on(foo))
  end

  def test_eval_scoping
    assert_in_out_err([], <<-INPUT, ["HELLO WORLD", "dlrow olleh", "HELLO WORLD"], [])
      module M
        refine String do
          def upcase
            reverse
          end
        end
      end

      puts "hello world".upcase
      puts eval(%{using M; "hello world".upcase})
      puts "hello world".upcase
    INPUT
  end

  def test_eval_with_binding_scoping
    assert_in_out_err([], <<-INPUT, ["HELLO WORLD", "dlrow olleh", "dlrow olleh"], [])
      module M
        refine String do
          def upcase
            reverse
          end
        end
      end

      puts "hello world".upcase
      b = binding
      puts eval(%{using M; "hello world".upcase}, b)
      puts eval(%{"hello world".upcase}, b)
    INPUT
  end

  def test_case_dispatch_is_aware_of_refinements
    assert_in_out_err([], <<-RUBY, ["refinement used"], [])
      module RefineSymbol
        refine Symbol do
          def ===(other)
            true
          end
        end
      end

      using RefineSymbol

      case :a
      when :b
        puts "refinement used"
      else
        puts "refinement not used"
      end
    RUBY
  end

  def test_refine_after_using
    assert_separately([], <<-"end;")
      bug8880 = '[ruby-core:57079] [Bug #8880]'
      module Test
        refine(String) do
        end
      end
      using Test
      def t
        'Refinements are broken!'.chop!
      end
      t
      module Test
        refine(String) do
          def chop!
            self.sub!(/broken/, 'fine')
          end
        end
      end
      assert_equal('Refinements are fine!', t, bug8880)
    end;
  end

  def test_instance_methods
    bug8881 = '[ruby-core:57080] [Bug #8881]'
    assert_not_include(Foo.instance_methods(false), :z, bug8881)
    assert_not_include(FooSub.instance_methods(true), :z, bug8881)
  end

  def test_method_defined
    assert_not_send([Foo, :method_defined?, :z])
    assert_not_send([FooSub, :method_defined?, :z])
  end

  def test_undef_refined_method
    bug8966 = '[ruby-core:57466] [Bug #8966]'

    assert_in_out_err([], <<-INPUT, ["NameError"], [], bug8966)
      module Foo
        refine Object do
          def foo
            puts "foo"
          end
        end
      end

      using Foo

      class Object
        begin
          undef foo
        rescue Exception => e
          p e.class
        end
      end
    INPUT

    assert_in_out_err([], <<-INPUT, ["NameError"], [], bug8966)
      module Foo
        refine Object do
          def foo
            puts "foo"
          end
        end
      end

      # without `using Foo'

      class Object
        begin
          undef foo
        rescue Exception => e
          p e.class
        end
      end
    INPUT
  end

  def test_refine_undefed_method_and_call
    assert_in_out_err([], <<-INPUT, ["NoMethodError"], [])
      class Foo
        def foo
        end

        undef foo
      end

      module FooExt
        refine Foo do
          def foo
          end
        end
      end

      begin
        Foo.new.foo
      rescue => e
        p e.class
      end
    INPUT
  end

  def test_refine_undefed_method_and_send
    assert_in_out_err([], <<-INPUT, ["NoMethodError"], [])
      class Foo
        def foo
        end

        undef foo
      end

      module FooExt
        refine Foo do
          def foo
          end
        end
      end

      begin
        Foo.new.send(:foo)
      rescue => e
        p e.class
      end
    INPUT
  end

  def test_adding_private_method
    bug9452 = '[ruby-core:60111] [Bug #9452]'

    assert_in_out_err([], <<-INPUT, ["Success!", "NoMethodError"], [], bug9452)
      module R
        refine Object do
          def m
            puts "Success!"
          end

          private(:m)
        end
      end

      using R

      m
      42.m rescue p($!.class)
    INPUT
  end

  def test_making_private_method_public
    bug9452 = '[ruby-core:60111] [Bug #9452]'

    assert_in_out_err([], <<-INPUT, ["Success!", "Success!"], [], bug9452)
        class Object
          private
          def m
          end
        end

        module R
          refine Object do
            def m
              puts "Success!"
            end
          end
        end

        using R
        m
        42.m
    INPUT
  end

  def test_refine_basic_object
    assert_separately([], <<-"end;")
    bug10106 = '[ruby-core:64166] [Bug #10106]'
    module RefinementBug
      refine BasicObject do
        def foo
          1
        end
      end
    end

    assert_raise(NoMethodError, bug10106) {Object.new.foo}
    end;

    assert_separately([], <<-"end;")
    bug10707 = '[ruby-core:67389] [Bug #10707]'
    module RefinementBug
      refine BasicObject do
        def foo
        end
      end
    end

    assert(methods, bug10707)
    assert_raise(NameError, bug10707) {method(:foo)}
    end;
  end

  def test_change_refined_new_method_visibility
    assert_separately([], <<-"end;")
    bug10706 = '[ruby-core:67387] [Bug #10706]'
    module RefinementBug
      refine Object do
        def foo
        end
      end
    end

    assert_raise(NameError, bug10706) {private(:foo)}
    end;
  end

  def test_alias_refined_method
    assert_separately([], <<-"end;")
    bug10731 = '[ruby-core:67523] [Bug #10731]'

    class C
    end

    module RefinementBug
      refine C do
        def foo
        end

        def bar
        end
      end
    end

    assert_raise(NameError, bug10731) do
      class C
        alias foo bar
      end
    end
    end;
  end

  def test_singleton_method_should_not_use_refinements
    assert_separately([], <<-"end;")
    bug10744 = '[ruby-core:67603] [Bug #10744]'

    class C
    end

    module RefinementBug
      refine C.singleton_class do
        def foo
        end
      end
    end

    assert_raise(NameError, bug10744) { C.singleton_method(:foo) }
    end;
  end

  def test_refined_method_defined
    assert_separately([], <<-"end;")
    bug10753 = '[ruby-core:67656] [Bug #10753]'

    c = Class.new do
      def refined_public; end
      def refined_protected; end
      def refined_private; end

      public :refined_public
      protected :refined_protected
      private :refined_private
    end

    m = Module.new do
      refine(c) do
        def refined_public; end
        def refined_protected; end
        def refined_private; end

        public :refined_public
        protected :refined_protected
        private :refined_private
      end
    end

    using m

    assert_equal(true, c.public_method_defined?(:refined_public), bug10753)
    assert_equal(false, c.public_method_defined?(:refined_protected), bug10753)
    assert_equal(false, c.public_method_defined?(:refined_private), bug10753)

    assert_equal(false, c.protected_method_defined?(:refined_public), bug10753)
    assert_equal(true, c.protected_method_defined?(:refined_protected), bug10753)
    assert_equal(false, c.protected_method_defined?(:refined_private), bug10753)

    assert_equal(false, c.private_method_defined?(:refined_public), bug10753)
    assert_equal(false, c.private_method_defined?(:refined_protected), bug10753)
    assert_equal(true, c.private_method_defined?(:refined_private), bug10753)
    end;
  end

  def test_undefined_refined_method_defined
    assert_separately([], <<-"end;")
    bug10753 = '[ruby-core:67656] [Bug #10753]'

    c = Class.new

    m = Module.new do
      refine(c) do
        def undefined_refined_public; end
        def undefined_refined_protected; end
        def undefined_refined_private; end
        public :undefined_refined_public
        protected :undefined_refined_protected
        private :undefined_refined_private
      end
    end

    using m

    assert_equal(false, c.public_method_defined?(:undefined_refined_public), bug10753)
    assert_equal(false, c.public_method_defined?(:undefined_refined_protected), bug10753)
    assert_equal(false, c.public_method_defined?(:undefined_refined_private), bug10753)

    assert_equal(false, c.protected_method_defined?(:undefined_refined_public), bug10753)
    assert_equal(false, c.protected_method_defined?(:undefined_refined_protected), bug10753)
    assert_equal(false, c.protected_method_defined?(:undefined_refined_private), bug10753)

    assert_equal(false, c.private_method_defined?(:undefined_refined_public), bug10753)
    assert_equal(false, c.private_method_defined?(:undefined_refined_protected), bug10753)
    assert_equal(false, c.private_method_defined?(:undefined_refined_private), bug10753)
    end;
  end

  def test_remove_refined_method
    assert_separately([], <<-"end;")
    bug10765 = '[ruby-core:67722] [Bug #10765]'

    class C
      def foo
        "C#foo"
      end
    end

    module RefinementBug
      refine C do
        def foo
          "RefinementBug#foo"
        end
      end
    end

    using RefinementBug

    class C
      remove_method :foo
    end

    assert_equal("RefinementBug#foo", C.new.foo, bug10765)
    end;
  end

  def test_remove_undefined_refined_method
    assert_separately([], <<-"end;")
    bug10765 = '[ruby-core:67722] [Bug #10765]'

    class C
    end

    module RefinementBug
      refine C do
        def foo
        end
      end
    end

    using RefinementBug

    assert_raise(NameError, bug10765) {
      class C
        remove_method :foo
      end
    }
    end;
  end

  module NotIncludeSuperclassMethod
    class X
      def foo
      end
    end

    class Y < X
    end

    module Bar
      refine Y do
        def foo
        end
      end
    end
  end

  def test_instance_methods_not_include_superclass_method
    bug10826 = '[ruby-dev:48854] [Bug #10826]'
    assert_not_include(NotIncludeSuperclassMethod::Y.instance_methods(false),
                       :foo, bug10826)
    assert_include(NotIncludeSuperclassMethod::Y.instance_methods(true),
                   :foo, bug10826)
  end

  def test_undef_original_method
    assert_in_out_err([], <<-INPUT, ["NoMethodError"], [])
      module NoPlus
        refine String do
          undef +
        end
      end

      using NoPlus
      "a" + "b" rescue p($!.class)
    INPUT
  end

  def test_undef_prepended_method
    bug13096 = '[ruby-core:78944] [Bug #13096]'
    klass = EnvUtil.labeled_class("X") do
      def foo; end
    end
    klass.prepend(Module.new)
    ext = EnvUtil.labeled_module("Ext") do
      refine klass do
        def foo
        end
      end
    end
    assert_nothing_raised(NameError, bug13096) do
      klass.class_eval do
        undef :foo
      end
    end
    ext
  end

  def test_call_refined_method_in_duplicate_module
    bug10885 = '[ruby-dev:48878]'
    assert_in_out_err([], <<-INPUT, [], [], bug10885)
      module M
        refine Object do
          def raise
            # do nothing
          end
        end

        class << self
          using M
          def m0
            raise
          end
        end

        using M
        def M.m1
          raise
        end
      end

      M.dup.m0
      M.dup.m1
    INPUT
  end

  def test_check_funcall_undefined
    bug11117 = '[ruby-core:69064] [Bug #11117]'

    x = Class.new
    Module.new do
      refine x do
        def to_regexp
          //
        end
      end
    end

    assert_nothing_raised(NoMethodError, bug11117) {
      assert_nil(Regexp.try_convert(x.new))
    }
  end

  def test_funcall_inherited
    bug11117 = '[ruby-core:69064] [Bug #11117]'

    Module.new {refine(Dir) {def to_s; end}}
    x = Class.new(Dir).allocate
    assert_nothing_raised(NoMethodError, bug11117) {
      x.inspect
    }
  end

  def test_alias_refined_method2
    bug11182 = '[ruby-core:69360]'
    assert_in_out_err([], <<-INPUT, ["C"], [], bug11182)
      class C
        def foo
          puts "C"
        end
      end

      module M
        refine C do
          def foo
            puts "Refined C"
          end
        end
      end

      class D < C
        alias bar foo
      end

      using M
      D.new.bar
    INPUT
  end

  def test_reopen_refinement_module
    assert_separately([], <<-"end;")
      $VERBOSE = nil
      class C
      end

      module R
        refine C do
          def m
            :foo
          end
        end
      end

      using R
      assert_equal(:foo, C.new.m)

      module R
        refine C do
          def m
            :bar
          end
        end
      end

      assert_equal(:bar, C.new.m, "[ruby-core:71423] [Bug #11672]")
    end;
  end

  module MixedUsing1
    class C
      def foo
        :orig_foo
      end
    end

    module R1
      refine C do
        def foo
          [:R1, super]
        end
      end
    end

    module_function

    def foo
      [:foo, C.new.foo]
    end

    using R1

    def bar
      [:bar, C.new.foo]
    end
  end

  module MixedUsing2
    class C
      def foo
        :orig_foo
      end
    end

    module R1
      refine C do
        def foo
          [:R1_foo, super]
        end
      end
    end

    module R2
      refine C do
        def bar
          [:R2_bar, C.new.foo]
        end

        using R1

        def baz
          [:R2_baz, C.new.foo]
        end
      end
    end

    using R2
    module_function
    def f1; C.new.bar; end
    def f2; C.new.baz; end
  end

  def test_mixed_using
    assert_equal([:foo, :orig_foo], MixedUsing1.foo)
    assert_equal([:bar, [:R1, :orig_foo]], MixedUsing1.bar)

    assert_equal([:R2_bar, :orig_foo], MixedUsing2.f1)
    assert_equal([:R2_baz, [:R1_foo, :orig_foo]], MixedUsing2.f2)
  end

  module MethodMissing
    class Foo
    end

    module Bar
      refine Foo  do
        def method_missing(mid, *args)
          "method_missing refined"
        end
      end
    end

    using Bar

    def self.call_undefined_method
      Foo.new.foo
    end
  end

  def test_method_missing
    assert_raise(NoMethodError) do
      MethodMissing.call_undefined_method
    end
  end

  module VisibleRefinements
    module RefA
      refine Object do
        def in_ref_a
        end
      end
    end

    module RefB
      refine Object do
        def in_ref_b
        end
      end
    end

    module RefC
      using RefA

      refine Object do
        def in_ref_c
        end
      end
    end

    module Foo
      using RefB
      USED_MODS = Module.used_modules
    end

    module Bar
      using RefC
      USED_MODS = Module.used_modules
    end

    module Combined
      using RefA
      using RefB
      USED_MODS = Module.used_modules
    end
  end

  def test_used_modules
    ref = VisibleRefinements
    assert_equal [], Module.used_modules
    assert_equal [ref::RefB], ref::Foo::USED_MODS
    assert_equal [ref::RefC], ref::Bar::USED_MODS
    assert_equal [ref::RefB, ref::RefA], ref::Combined::USED_MODS
  end

  def test_warn_setconst_in_refinmenet
    bug10103 = '[ruby-core:64143] [Bug #10103]'
    warnings = [
      "-:3: warning: not defined at the refinement, but at the outer class/module",
      "-:4: warning: not defined at the refinement, but at the outer class/module"
    ]
    assert_in_out_err([], <<-INPUT, [], warnings, bug10103)
      module M
        refine String do
          FOO = 123
          @@foo = 456
        end
      end
    INPUT
  end

  def test_symbol_proc
    assert_equal("FooExt#x", FooExtClient.map_x_on(Foo.new))
    assert_equal("Foo#x", FooExtClient.return_proc(&:x).(Foo.new))
  end

  def test_symbol_proc_with_block
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    bug = '[ruby-core:80219] [Bug #13325]'
    begin;
      module M
        refine Class.new do
        end
      end
      class C
        def call(a, x, &b)
          b.call(a, &x)
        end
      end
      o = C.new
      r = nil
      x = ->(z){r = z}
      assert_equal(42, o.call(42, x, &:tap))
      assert_equal(42, r)
      using M
      r = nil
      assert_equal(42, o.call(42, x, &:tap), bug)
      assert_equal(42, r, bug)
    end;
  end

  module AliasInSubclass
    class C
      def foo
        :original
      end
    end

    class D < C
      alias bar foo
    end

    module M
      refine D do
        def bar
          :refined
        end
      end
    end
  end

  def test_refine_alias_in_subclass
    assert_equal(:refined,
                 eval_using(AliasInSubclass::M, "AliasInSubclass::D.new.bar"))
  end

  def test_refine_with_prepend
    assert_separately([], "#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
      bug = '[ruby-core:78073] [Bug #12920]'
      Integer.prepend(Module.new)
      Module.new do
        refine Integer do
          define_method(:+) {}
        end
      end
      assert_kind_of(Time, Time.now, bug)
    end;
  end

  def test_public_in_refine
    assert_separately([], "#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
      bug12729 = '[ruby-core:77161] [Bug #12729]'

      class Cow
        private
        def moo() "Moo"; end
      end

      module PublicCows
        refine(Cow) {
          public :moo
        }
      end

      using PublicCows
      assert_equal("Moo", Cow.new.moo, bug12729)
    end;
  end

  module SuperToModule
    class Parent
    end

    class Child < Parent
    end

    module FooBar
      refine Parent do
        def to_s
          "Parent"
        end
      end

      refine Child do
        def to_s
          super + " -> Child"
        end
      end
    end

    using FooBar
    def Child.test
      new.to_s
    end
  end

  def test_super_to_module
    bug = '[ruby-core:79588] [Bug #13227]'
    assert_equal("Parent -> Child", SuperToModule::Child.test, bug)
  end

  def test_include_refinement
    bug = '[ruby-core:79632] [Bug #13236] cannot include refinement module'
    r = nil
    m = Module.new do
      r = refine(String) {def test;:ok end}
    end
    assert_raise_with_message(ArgumentError, /refinement/, bug) do
      m.module_eval {include r}
    end
    assert_raise_with_message(ArgumentError, /refinement/, bug) do
      m.module_eval {prepend r}
    end
  end

  class ParentDefiningPrivateMethod
    private
    def some_inherited_method
    end
  end

  module MixinDefiningPrivateMethod
    private
    def some_included_method
    end
  end

  class SomeChildClassToRefine < ParentDefiningPrivateMethod
    include MixinDefiningPrivateMethod

    private
    def some_method
    end
  end

  def test_refine_inherited_method_with_visibility_changes
    Module.new do
      refine(SomeChildClassToRefine) do
        def some_inherited_method; end
        def some_included_method; end
        def some_method; end
      end
    end

    obj = SomeChildClassToRefine.new

    assert_raise_with_message(NoMethodError, /private/) do
      obj.some_inherited_method
    end

    assert_raise_with_message(NoMethodError, /private/) do
      obj.some_included_method
    end

    assert_raise_with_message(NoMethodError, /private/) do
      obj.some_method
    end
  end

  def test_refined_method_alias_warning
    c = Class.new do
      def t; :t end
      def f; :f end
    end
    Module.new do
      refine(c) do
        alias foo t
      end
    end
    assert_warning('', '[ruby-core:82385] [Bug #13817] refined method is not redefined') do
      c.class_eval do
        alias foo f
      end
    end
  end

  def test_using_wrong_argument
    bug = '[ruby-dev:50270] [Bug #13956]'
    pattern = /expected Module/
    assert_separately([], "#{<<-"begin;"}\n#{<<-'end;'}")
    bug = ""#{bug.dump}
    pattern = /#{pattern}/
    begin;
      assert_raise_with_message(TypeError, pattern, bug) {
        using(1) do end
      }
    end;
    assert_separately([], "#{<<-"begin;"}\n#{<<-'end;'}")
    bug = ""#{bug.dump}
    pattern = /#{pattern}/
    begin;
      assert_raise_with_message(TypeError, pattern, bug) {
        Module.new {using(1) {}}
      }
    end;
  end

  class ToString
    c = self
    using Module.new {refine(c) {def to_s; "ok"; end}}
    def string
      "#{self}"
    end
  end

  def test_tostring
    assert_equal("ok", ToString.new.string)
  end

  class ToSymbol
    c = self
    using Module.new {refine(c) {def intern; "<#{upcase}>"; end}}
    def symbol
      :"#{@string}"
    end
    def initialize(string)
      @string = string
    end
  end

  def test_dsym_literal
    assert_equal(:foo, ToSymbol.new("foo").symbol)
  end

  module ToProc
    def self.call &block
      block.call
    end

    class ReturnProc
      c = self
      using Module.new {
        refine c do
          def to_proc
            proc { "to_proc" }
          end
        end
      }
      def call
        ToProc.call(&self)
      end
    end

    class ReturnNoProc
      c = self
      using Module.new {
        refine c do
          def to_proc
            true
          end
        end
      }

      def call
        ToProc.call(&self)
      end
    end

    class PrivateToProc
      c = self
      using Module.new {
        refine c do
          private
          def to_proc
            proc { "private_to_proc" }
          end
        end
      }

      def call
        ToProc.call(&self)
      end
    end


    class NonProc
      def call
        ToProc.call(&self)
      end
    end

    class MethodMissing
      def method_missing *args
        proc { "method_missing" }
      end

      def call
        ToProc.call(&self)
      end
    end

    class ToProcAndMethodMissing
      def method_missing *args
        proc { "method_missing" }
      end

      c = self
      using Module.new {
        refine c do
          def to_proc
            proc { "to_proc" }
          end
        end
      }

      def call
        ToProc.call(&self)
      end
    end

    class ToProcAndRefinements
      def to_proc
        proc { "to_proc" }
      end

      c = self
      using Module.new {
        refine c do
          def to_proc
            proc { "refinements_to_proc" }
          end
        end
      }

      def call
        ToProc.call(&self)
      end
    end
  end

  def test_to_proc
    assert_equal("to_proc", ToProc::ReturnProc.new.call)
    assert_equal("private_to_proc", ToProc::PrivateToProc.new.call)
    assert_raise(TypeError){ ToProc::ReturnNoProc.new.call }
    assert_raise(TypeError){ ToProc::NonProc.new.call }
    assert_equal("method_missing", ToProc::MethodMissing.new.call)
    assert_equal("to_proc", ToProc::ToProcAndMethodMissing.new.call)
    assert_equal("refinements_to_proc", ToProc::ToProcAndRefinements.new.call)
  end

  def test_unused_refinement_for_module
    bug14068 = '[ruby-core:83613] [Bug #14068]'
    assert_in_out_err([], <<-INPUT, ["M1#foo"], [], bug14068)
      module M1
        def foo
          puts "M1#foo"
        end
      end

      module M2
      end

      module UnusedRefinement
        refine(M2) do
          def foo
            puts "M2#foo"
          end
        end
      end

      include M1
      include M2
      foo()
    INPUT
  end

  def test_refining_module_repeatedly
    bug14070 = '[ruby-core:83617] [Bug #14070]'
    assert_in_out_err([], <<-INPUT, ["ok"], [], bug14070)
      1000.times do
        Class.new do
          include Enumerable
        end

        Module.new do
          refine Enumerable do
            def foo
            end
          end
        end
      end
      puts "ok"
    INPUT
  end

  def test_call_method_in_unused_refinement
    bug15720 = '[ruby-core:91916] [Bug #15720]'
    assert_in_out_err([], <<-INPUT, ["ok"], [], bug15720)
      module M1
        refine Kernel do
          def foo
            'foo called!'
          end
        end
      end

      module M2
        refine Kernel do
          def bar
            'bar called!'
          end
        end
      end

      using M1

      foo

      begin
        bar
      rescue NameError
      end

      puts "ok"
    INPUT
  end

  def test_super_from_refined_module
    a = EnvUtil.labeled_module("A") do
      def foo;"[A#{super}]";end
    end
    b = EnvUtil.labeled_class("B") do
      def foo;"[B]";end
    end
    c = EnvUtil.labeled_class("C", b) do
      include a
      def foo;"[C#{super}]";end
    end
    d = EnvUtil.labeled_module("D") do
      refine(a) do
        def foo;end
      end
    end
    assert_equal("[C[A[B]]]", c.new.foo, '[ruby-dev:50390] [Bug #14232]')
    d
  end

  class RefineInUsing
    module M1
      refine RefineInUsing do
        def foo
          :ok
        end
      end
    end

    module M2
      using M1
      refine RefineInUsing do
        def call_foo
	  RefineInUsing.new.foo
        end
      end
    end

    using M2
    def self.test
      new.call_foo
    end
  end

  def test_refine_in_using
    assert_equal(:ok, RefineInUsing.test)
  end

  class Bug16242
    module OtherM
    end

    module M
      prepend OtherM

      refine M do
        def refine_method
          "refine_method"
        end
      end
      using M

      def hoge
        refine_method
      end
    end

    class X
      include M
    end
  end

  def test_refine_prepended_module
    assert_equal("refine_method", Bug16242::X.new.hoge)
  end

  module Bug13446
    module Enumerable
      def sum(*args)
        i = 0
        args.each { |arg| i += a }
        i
      end
    end

    using Module.new {
      refine Enumerable do
        alias :orig_sum :sum
      end
    }

    module Enumerable
      def sum(*args)
        orig_sum(*args)
      end
    end

    class GenericEnumerable
      include Enumerable
    end

    Enumerable.prepend(Module.new)
  end

  def test_prepend_refined_module
    assert_equal(0, Bug13446::GenericEnumerable.new.sum)
  end

  def test_unbound_refine_method
    a = EnvUtil.labeled_class("A") do
      def foo
        self.class
      end
    end
    b = EnvUtil.labeled_class("B")
    bar = EnvUtil.labeled_module("R") do
      break refine a do
        def foo
          super
        end
      end
    end
    assert_raise(TypeError) do
      bar.instance_method(:foo).bind(b.new)
    end
  end

  def test_refine_frozen_class
    verbose_bak, $VERBOSE = $VERBOSE, nil
    singleton_class.instance_variable_set(:@x, self)
    class << self
      c = Class.new do
        def foo
          :cfoo
        end
      end
      foo = Module.new do
        refine c do
          def foo
            :rfoo
          end
        end
      end
      using foo
      @x.assert_equal(:rfoo, c.new.foo)
      c.freeze
      foo.module_eval do
        refine c do
          def foo
            :rfoo2
          end
          def bar
            :rbar
          end
        end
      end
      @x.assert_equal(:rfoo2, c.new.foo)
      @x.assert_equal(:rbar, c.new.bar, '[ruby-core:71391] [Bug #11669]')
    end
  ensure
    $VERBOSE = verbose_bak
  end

  private

  def eval_using(mod, s)
    eval("using #{mod}; #{s}", Sandbox::BINDING)
  end
end
