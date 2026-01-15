# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class EqualityTest < TestCase
    def test_equality
      assert_operator Prism.parse_statement("1"), :===, Prism.parse_statement("1")
      assert_operator Prism.parse("1").value, :===, Prism.parse("1").value

      complex_source = "class Something; @var = something.else { _1 }; end"
      assert_operator Prism.parse_statement(complex_source), :===, Prism.parse_statement(complex_source)

      refute_operator Prism.parse_statement("1"), :===, Prism.parse_statement("2")
      refute_operator Prism.parse_statement("1"), :===, Prism.parse_statement("0x1")

      complex_source_1 = "class Something; @var = something.else { _1 }; end"
      complex_source_2 = "class Something; @var = something.else { _2 }; end"
      refute_operator Prism.parse_statement(complex_source_1), :===, Prism.parse_statement(complex_source_2)
    end
  end
end
