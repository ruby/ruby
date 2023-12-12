# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class AttributeWriteTest < TestCase
    module Target
      def self.value
        2
      end

      def self.value=(value)
        2
      end

      def self.[]=(index, value)
        2
      end
    end

    def test_named_call_with_operator
      assert_attribute_write("Target.value = 1")
    end

    def test_named_call_without_operator
      assert_attribute_write("Target.value=(1)")
    end

    def test_indexed_call_with_operator
      assert_attribute_write("Target[0] = 1")
    end

    def test_indexed_call_without_operator
      refute_attribute_write("Target.[]=(0, 1)")
    end

    def test_comparison_operators
      refute_attribute_write("Target.value == 1")
      refute_attribute_write("Target.value === 1")
    end

    private

    def parse(source)
      Prism.parse(source).value.statements.body.first
    end

    def assert_attribute_write(source)
      call = parse(source)
      assert(call.attribute_write?)
      assert_equal(1, eval(source))
    end

    def refute_attribute_write(source)
      call = parse(source)
      refute(call.attribute_write?)
      refute_equal(1, eval(source))
    end
  end
end
