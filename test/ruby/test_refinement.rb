require 'test/unit'
require_relative 'envutil'

# to supress warnings for future calls of Module#refine
EnvUtil.suppress_warning do
  Module.new {
    refine(Object) {}
  }
end

class TestRefinement < Test::Unit::TestCase
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

  eval <<-EOF, TOPLEVEL_BINDING
    using TestRefinement::FooExt

    class TestRefinement::FooExtClient
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

      def self.method_z(foo)
        return foo.method(:z)
      end

      def self.invoke_call_x_on(foo)
        return foo.call_x
      end
    end
  EOF

  eval <<-EOF, TOPLEVEL_BINDING
    using TestRefinement::FooExt
    using TestRefinement::FooExt2

    class TestRefinement::FooExtClient2
      def self.invoke_y_on(foo)
        return foo.y
      end

      def self.invoke_a_on(foo)
        return foo.a
      end
    end
  EOF

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

  def test_send_should_not_use_refinements
    foo = Foo.new
    assert_raise(NoMethodError) { foo.send(:z) }
    assert_raise(NoMethodError) { FooExtClient.send_z_on(foo) }
    assert_raise(NoMethodError) { foo.send(:z) }

    assert_equal(true, RespondTo::Sub.new.respond_to?(:foo))
  end

  def test_method_should_not_use_refinements
    foo = Foo.new
    assert_raise(NameError) { foo.method(:z) }
    assert_raise(NameError) { FooExtClient.method_z(foo) }
    assert_raise(NameError) { foo.method(:z) }
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

  module FixnumSlashExt
    refine Fixnum do
      def /(other) quo(other) end
    end
  end

  def test_override_builtin_method
    assert_equal(0, 1 / 2)
    assert_equal(Rational(1, 2), eval_using(FixnumSlashExt, "1 / 2"))
    assert_equal(0, 1 / 2)
  end

  module FixnumPlusExt
    refine Fixnum do
      def self.method_added(*args); end
      def +(other) "overridden" end
    end
  end

  def test_override_builtin_method_with_method_added
    assert_equal(3, 1 + 2)
    assert_equal("overridden", eval_using(FixnumPlusExt, "1 + 2"))
    assert_equal(3, 1 + 2)
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

  module RefineSameClass
    REFINEMENT1 = refine(Fixnum) {
      def foo; return "foo" end
    }
    REFINEMENT2 = refine(Fixnum) {
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

  module FixnumFooExt
    refine Fixnum do
      def foo; "foo"; end
    end
  end

  def test_respond_to_should_not_use_refinements
    assert_equal(false, 1.respond_to?(:foo))
    assert_equal(false, eval_using(FixnumFooExt, "1.respond_to?(:foo)"))
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

  def test_refine_module
    m1 = Module.new
    assert_raise(TypeError) do
      Module.new {
        refine m1 do
        def foo
          :m2
        end
        end
      }
    end
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
        refine Fixnum do
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
      eval("self.using Module.new", TOPLEVEL_BINDING)
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
    c = Class.new
    assert_raise(TypeError) do
      eval("using TestRefinement::UsingClass", TOPLEVEL_BINDING)
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
      Fixnum = refine(Fixnum) {}
    end
  end

  def test_inspect
    assert_equal("#<refinement:Fixnum@TestRefinement::Inspect::M>",
                 Inspect::M::Fixnum.inspect)
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
      def foo
        "redefined"
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
      eval(<<-EOF, TOPLEVEL_BINDING)
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
      eval(<<-EOF, TOPLEVEL_BINDING)
        $main = self
        module M
        end
        def call_using_in_method
          $main.send(:using, M)
        end
        call_using_in_method
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

  eval <<-EOF, TOPLEVEL_BINDING
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

  eval <<-EOF, TOPLEVEL_BINDING
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
      eval <<-EOF, TOPLEVEL_BINDING
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
    assert_in_out_err([], <<-INPUT, ["HELLO WORLD", "dlrow olleh", "HELLO WORLD"], [])
      module M
        refine String do
          def upcase
            reverse
          end
        end
      end

      puts "hello world".upcase
      puts eval(%{using M; "hello world".upcase}, TOPLEVEL_BINDING)
      puts eval(%{"hello world".upcase}, TOPLEVEL_BINDING)
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

  private

  def eval_using(mod, s)
    eval("using #{mod}; #{s}", TOPLEVEL_BINDING)
  end
end
