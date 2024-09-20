# frozen_string_literal: true

require_relative "../test_helper"

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

    def test_parse_file_comments_error
      error = assert_raise Errno::ENOENT do
        Prism.parse_file_comments("idontexist.rb")
      end

      assert_equal "No such file or directory - idontexist.rb", error.message

      assert_raise TypeError do
        Prism.parse_file_comments(nil)
      end
    end
  end
end
