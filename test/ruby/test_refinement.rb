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
      def +(other) "overriden" end
    end
  end

  def test_override_builtin_method_with_method_added
    assert_equal(3, 1 + 2)
    assert_equal("overriden", eval_using(FixnumPlusExt, "1 + 2"))
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
    assert_in_out_err([], <<-INPUT, %w(:C :M), /Refinements are experimental/)
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

  def test_no_module_using
    assert_raise(NoMethodError) do
      Module.new {
        using Module.new
      }
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
    e = assert_raise(ArgumentError) {
      Module.new do
        refine c1
      end
    }
    assert_equal("no block given", e.message)
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
    assert_in_out_err([], <<-INPUT, %w(:M1 :M2), /Refinements are experimental/)
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

  def test_case_dispatch_is_aware_of_refinements
    assert_in_out_err([], <<-RUBY, ["refinement used"], [])
      $VERBOSE = nil #to suppress warning "Refinements are experimental, ..."
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
      $VERBOSE = nil #to suppress warning "Refinements are experimental, ..."
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
      $VERBOSE = nil #to suppress warning "Refinements are experimental, ..."
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
      $VERBOSE = nil #to suppress warning "Refinements are experimental, ..."
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
      $VERBOSE = nil #to suppress warning "Refinements are experimental, ..."
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
      $VERBOSE = nil #to suppress warning "Refinements are experimental, ..."
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
        $VERBOSE = nil #to suppress warning "Refinements are experimental, ..."
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

  private

  def eval_using(mod, s)
    eval("using #{mod}; #{s}", TOPLEVEL_BINDING)
  end
end
