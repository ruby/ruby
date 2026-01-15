# frozen_string_literal: true
# typed: ignore

require_relative "../test_helper"

module Prism
  class CompilerTest < TestCase
    class SExpressions < Prism::Compiler
      def visit_arguments_node(node)
        [:arguments, super]
      end

      def visit_call_node(node)
        [:call, super]
      end

      def visit_integer_node(node)
        [:integer]
      end

      def visit_program_node(node)
        [:program, super]
      end
    end

    def test_compiler
      expected = [:program, [[[:call, [[:integer], [:arguments, [[:integer]]]]]]]]
      assert_equal expected, Prism.parse("1 + 2").value.accept(SExpressions.new)
    end
  end
end
