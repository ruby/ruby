# frozen_string_literal: false
require 'psych/helper'

module Psych
  class TestSafeLoad < TestCase
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
      assert_equal(x, Psych.safe_load(Psych.dump(x), [], [], true))
    end

    def test_symbol_whitelist
      yml = Psych.dump :foo
      assert_raises(Psych::DisallowedClass) do
        Psych.safe_load yml
      end
      assert_equal(:foo, Psych.safe_load(yml, [Symbol], [:foo]))
    end

    def test_symbol
      assert_raises(Psych::DisallowedClass) do
        assert_safe_cycle :foo
      end
      assert_raises(Psych::DisallowedClass) do
        Psych.safe_load '--- !ruby/symbol foo', []
      end
      assert_safe_cycle :foo, [Symbol]
      assert_safe_cycle :foo, %w{ Symbol }
      assert_equal :foo, Psych.safe_load('--- !ruby/symbol foo', [Symbol])
    end

    def test_foo
      assert_raises(Psych::DisallowedClass) do
        Psych.safe_load '--- !ruby/object:Foo {}', [Foo]
      end
      assert_raises(Psych::DisallowedClass) do
        assert_safe_cycle Foo.new
      end
      assert_kind_of(Foo, Psych.safe_load(Psych.dump(Foo.new), [Foo]))
    end

    X = Struct.new(:x)
    def test_struct_depends_on_sym
      assert_safe_cycle(X.new, [X, Symbol])
      assert_raises(Psych::DisallowedClass) do
        cycle X.new, [X]
      end
    end

    def test_anon_struct
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

    private

    def cycle object, whitelist = []
      Psych.safe_load(Psych.dump(object), whitelist)
    end

    def assert_safe_cycle object, whitelist = []
      other = cycle object, whitelist
      assert_equal object, other
    end
  end
end
