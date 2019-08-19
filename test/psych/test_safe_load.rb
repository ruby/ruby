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
      assert_raises(Psych::BadAlias) do
        Psych.safe_load Psych.dump(x)
      end
    end

    def test_explicit_recursion
      x = []
      x << x
      assert_equal(x, Psych.safe_load(Psych.dump(x), permitted_classes: [], permitted_symbols: [], aliases: true))
      # deprecated interface
      assert_equal(x, Psych.safe_load(Psych.dump(x), [], [], true))
    end

    def test_permitted_symbol
      yml = Psych.dump :foo
      assert_raises(Psych::DisallowedClass) do
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

      # deprecated interface
      assert_equal(:foo, Psych.safe_load(yml, [Symbol], [:foo]))
    end

    def test_symbol
      assert_raises(Psych::DisallowedClass) do
        assert_safe_cycle :foo
      end
      assert_raises(Psych::DisallowedClass) do
        Psych.safe_load '--- !ruby/symbol foo', permitted_classes: []
      end

      # deprecated interface
      assert_raises(Psych::DisallowedClass) do
        Psych.safe_load '--- !ruby/symbol foo', []
      end

      assert_safe_cycle :foo, permitted_classes: [Symbol]
      assert_safe_cycle :foo, permitted_classes: %w{ Symbol }
      assert_equal :foo, Psych.safe_load('--- !ruby/symbol foo', permitted_classes: [Symbol])

      # deprecated interface
      assert_equal :foo, Psych.safe_load('--- !ruby/symbol foo', [Symbol])
    end

    def test_foo
      assert_raises(Psych::DisallowedClass) do
        Psych.safe_load '--- !ruby/object:Foo {}', permitted_classes: [Foo]
      end

      # deprecated interface
      assert_raises(Psych::DisallowedClass) do
        Psych.safe_load '--- !ruby/object:Foo {}', [Foo]
      end

      assert_raises(Psych::DisallowedClass) do
        assert_safe_cycle Foo.new
      end
      assert_kind_of(Foo, Psych.safe_load(Psych.dump(Foo.new), permitted_classes: [Foo]))

      # deprecated interface
      assert_kind_of(Foo, Psych.safe_load(Psych.dump(Foo.new), [Foo]))
    end

    X = Struct.new(:x)
    def test_struct_depends_on_sym
      assert_safe_cycle(X.new, permitted_classes: [X, Symbol])
      assert_raises(Psych::DisallowedClass) do
        cycle X.new, permitted_classes: [X]
      end
    end

    def test_anon_struct
      assert Psych.safe_load(<<-eoyml, permitted_classes: [Struct, Symbol])
--- !ruby/struct
  foo: bar
                      eoyml

      assert_raises(Psych::DisallowedClass) do
        Psych.safe_load(<<-eoyml, permitted_classes: [Struct])
--- !ruby/struct
  foo: bar
                      eoyml
      end

      assert_raises(Psych::DisallowedClass) do
        Psych.safe_load(<<-eoyml, permitted_classes: [Symbol])
--- !ruby/struct
  foo: bar
                      eoyml
      end
    end

    def test_deprecated_anon_struct
      assert Psych.safe_load(<<-eoyml, [Struct, Symbol])
--- !ruby/struct
  foo: bar
                      eoyml

      assert_raises(Psych::DisallowedClass) do
        Psych.safe_load(<<-eoyml, [Struct])
--- !ruby/struct
  foo: bar
                      eoyml
      end

      assert_raises(Psych::DisallowedClass) do
        Psych.safe_load(<<-eoyml, [Symbol])
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
      assert_raises(Psych::SyntaxError) { Psych.safe_load("--- `") }
    end

    private

    def cycle object, permitted_classes: []
      Psych.safe_load(Psych.dump(object), permitted_classes: permitted_classes)
      # deprecated interface test
      Psych.safe_load(Psych.dump(object), permitted_classes)
    end

    def assert_safe_cycle object, permitted_classes: []
      other = cycle object, permitted_classes: permitted_classes
      assert_equal object, other
    end
  end
end
