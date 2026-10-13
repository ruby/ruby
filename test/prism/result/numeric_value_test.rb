# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
  class NumericValueTest < TestCase
    def test_numeric_value
      assert_equal 123, Ruby::Prism.parse_statement("123").value
      assert_equal 123, Ruby::Prism.parse_statement("1_23").value
      assert_equal 3.14, Ruby::Prism.parse_statement("3.14").value
      assert_equal 3.14, Ruby::Prism.parse_statement("3.1_4").value
      assert_equal 42i, Ruby::Prism.parse_statement("42i").value
      assert_equal 42i, Ruby::Prism.parse_statement("4_2i").value
      assert_equal 42.1ri, Ruby::Prism.parse_statement("42.1ri").value
      assert_equal 42.1ri, Ruby::Prism.parse_statement("42.1_0ri").value
      assert_equal 3.14i, Ruby::Prism.parse_statement("3.14i").value
      assert_equal 3.14i, Ruby::Prism.parse_statement("3.1_4i").value
      assert_equal 42r, Ruby::Prism.parse_statement("42r").value
      assert_equal 42r, Ruby::Prism.parse_statement("4_2r").value
      assert_equal 0.5r, Ruby::Prism.parse_statement("0.5r").value
      assert_equal 0.5r, Ruby::Prism.parse_statement("0.5_0r").value
      assert_equal 42ri, Ruby::Prism.parse_statement("42ri").value
      assert_equal 42ri, Ruby::Prism.parse_statement("4_2ri").value
      assert_equal 0.5ri, Ruby::Prism.parse_statement("0.5ri").value
      assert_equal 0.5ri, Ruby::Prism.parse_statement("0.5_0ri").value
      assert_equal 0xFFr, Ruby::Prism.parse_statement("0xFFr").value
      assert_equal 0xFFr, Ruby::Prism.parse_statement("0xF_Fr").value
      assert_equal 0xFFri, Ruby::Prism.parse_statement("0xFFri").value
      assert_equal 0xFFri, Ruby::Prism.parse_statement("0xF_Fri").value
    end
  end
end
