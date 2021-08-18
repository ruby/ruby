# frozen_string_literal: true
require 'psych/helper'

module Psych
  class TestSafeLoad < TestCase
    def setup
      @orig_verbose, $VERBOSE = $VERBOSE, nil
    end

    def teardown
      $VERBOSE = @orig_verbose
    end

    class Foo; end

    [1, 2.2, {}, [], "foo"].each do |obj|
      define_method(:"test_basic_#{obj.class}") do
        assert_safe_cycle obj
      end
    end

    def test_no_recursion
      x = []
      x << x
      assert_raise(Psych::BadAlias) do
        Psych.safe_load Psych.dump(x)
      end
    end

    def test_explicit_recursion
      x = []
      x << x
      assert_equal(x, Psych.safe_load(Psych.dump(x), permitted_classes: [], permitted_symbols: [], aliases: true))
    end

    def test_permitted_symbol
      yml = Psych.dump :foo
      assert_raise(Psych::DisallowedClass) do
        Psych.safe_load yml
      end
      assert_equal(
        :foo,
        Psych.safe_load(
          yml,
          permitted_classes: [Symbol],
          permitted_symbols: [:foo]
        )
      )
    end

    def test_symbol
      assert_raise(Psych::DisallowedClass) do
        assert_safe_cycle :foo
      end
      assert_raise(Psych::DisallowedClass) do
        Psych.safe_load '--- !ruby/symbol foo', permitted_classes: []
      end

      assert_safe_cycle :foo, permitted_classes: [Symbol]
      assert_safe_cycle :foo, permitted_classes: %w{ Symbol }
      assert_equal :foo, Psych.safe_load('--- !ruby/symbol foo', permitted_classes: [Symbol])
    end

    def test_foo
      assert_raise(Psych::DisallowedClass) do
        Psych.safe_load '--- !ruby/object:Foo {}', permitted_classes: [Foo]
      end

      assert_raise(Psych::DisallowedClass) do
        assert_safe_cycle Foo.new
      end
      assert_kind_of(Foo, Psych.safe_load(Psych.dump(Foo.new), permitted_classes: [Foo]))
    end

    X = Struct.new(:x)
    def test_struct_depends_on_sym
      assert_safe_cycle(X.new, permitted_classes: [X, Symbol])
      assert_raise(Psych::DisallowedClass) do
        cycle X.new, permitted_classes: [X]
      end
    end

    def test_anon_struct
      assert Psych.safe_load(<<-eoyml, permitted_classes: [Struct, Symbol])
--- !ruby/struct
  foo: bar
                      eoyml

      assert_raise(Psych::DisallowedClass) do
        Psych.safe_load(<<-eoyml, permitted_classes: [Struct])
--- !ruby/struct
  foo: bar
                      eoyml
      end

      assert_raise(Psych::DisallowedClass) do
        Psych.safe_load(<<-eoyml, permitted_classes: [Symbol])
--- !ruby/struct
  foo: bar
                      eoyml
      end
    end

    def test_safe_load_default_fallback
      assert_nil Psych.safe_load("")
    end

    def test_safe_load
      assert_equal %w[a b], Psych.safe_load("- a\n- b")
    end

    def test_safe_load_raises_on_bad_input
      assert_raise(Psych::SyntaxError) { Psych.safe_load("--- `") }
    end

    private

    def cycle object, permitted_classes: []
      Psych.safe_load(Psych.dump(object), permitted_classes: permitted_classes)
    end

    def assert_safe_cycle object, permitted_classes: []
      other = cycle object, permitted_classes: permitted_classes
      assert_equal object, other
    end
  end
end
