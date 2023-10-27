# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class ParseInlineCommentsTest < TestCase
    def test_parse_inline_comments
      comments = Prism.parse_inline_comments("# foo")

      assert_kind_of Array, comments
      assert_equal 1, comments.length
    end

    def test_parse_file_inline_comments
      comments = Prism.parse_file_inline_comments(__FILE__)

      assert_kind_of Array, comments
      assert_equal 1, comments.length
    end
  end
end
