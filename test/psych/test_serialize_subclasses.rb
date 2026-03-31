# frozen_string_literal: true
require_relative 'helper'

module Psych
  class TestSerializeSubclasses < TestCase
    class SomeObject
      def initialize one, two
        @one = one
        @two = two
      end

      def == other
        @one == other.instance_eval { @one } &&
          @two == other.instance_eval { @two }
      end
    end

    def test_some_object
      so = SomeObject.new('foo', [1,2,3])
      assert_equal so, Psych.unsafe_load(Psych.dump(so))
    end

    class StructSubclass < Struct.new(:foo)
      def initialize foo, bar
        super(foo)
        @bar = bar
      end

      def == other
        super(other) && @bar == other.instance_eval{ @bar }
      end
    end

    def test_struct_subclass
      so = StructSubclass.new('foo', [1,2,3])
      assert_equal so, Psych.unsafe_load(Psych.dump(so))
    end

    class DataSubclass < Data.define(:foo)
      def initialize(foo:)
        @bar = "hello #{foo}"
        super(foo: foo)
      end

      def == other
        super(other) && @bar == other.instance_eval{ @bar }
      end
    end unless RUBY_VERSION < "3.2"

    def test_data_subclass
      omit "Data requires ruby >= 3.2" if RUBY_VERSION < "3.2"
      so = DataSubclass.new('foo')
      assert_equal so, Psych.unsafe_load(Psych.dump(so))
    end

  end
end
