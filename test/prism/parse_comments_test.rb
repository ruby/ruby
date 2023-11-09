# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class ParseCommentsTest < TestCase
    def test_parse_comments
      comments = Prism.parse_comments("# foo")

      assert_kind_of Array, comments
      assert_equal 1, comments.length
    end

    def test_parse_file_comments
      comments = Prism.parse_file_comments(__FILE__)

      assert_kind_of Array, comments
      assert_equal 1, comments.length
    end
  end
end
