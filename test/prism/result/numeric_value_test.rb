# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class NumericValueTest < TestCase
    def test_numeric_value
      assert_equal 123, Prism.parse_statement("123").value
      assert_equal 3.14, Prism.parse_statement("3.14").value
      assert_equal 42i, Prism.parse_statement("42i").value
      assert_equal 42.1ri, Prism.parse_statement("42.1ri").value
      assert_equal 3.14i, Prism.parse_statement("3.14i").value
      assert_equal 42r, Prism.parse_statement("42r").value
      assert_equal 0.5r, Prism.parse_statement("0.5r").value
      assert_equal 42ri, Prism.parse_statement("42ri").value
      assert_equal 0.5ri, Prism.parse_statement("0.5ri").value
      assert_equal 0xFFr, Prism.parse_statement("0xFFr").value
      assert_equal 0xFFri, Prism.parse_statement("0xFFri").value
    end
  end
end
