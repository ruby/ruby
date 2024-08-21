# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class LexTest < TestCase
    def test_lex_result
      result = Prism.lex("")
      assert_kind_of LexResult, result

      result = Prism.lex_file(__FILE__)
      assert_kind_of LexResult, result
    end

    def test_parse_lex_result
      result = Prism.parse_lex("")
      assert_kind_of ParseLexResult, result

      result = Prism.parse_lex_file(__FILE__)
      assert_kind_of ParseLexResult, result
    end
  end
end
