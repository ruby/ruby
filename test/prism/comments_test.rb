# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class CommentsTest < TestCase
    def test_comment_inline
      source = "# comment"

      assert_comment source, :inline, [0, 9, 1, 1, 0, 9]
      assert_equal [0], Debug.newlines(source)
    end

    def test_comment_inline_def
      source = <<~RUBY
      def foo
        # a comment
      end
      RUBY

      assert_comment source, :inline, [10, 21, 2, 2, 2, 13]
    end

    def test_comment___END__
      source = <<~RUBY
        __END__
        comment
      RUBY

      assert_comment source, :__END__, [0, 16, 1, 2, 0, 0]
    end

    def test_comment___END__crlf
      source = "__END__\r\ncomment\r\n"

      assert_comment source, :__END__, [0, 18, 1, 2, 0, 0]
    end

    def test_comment_embedded_document
      source = <<~RUBY
        =begin
        comment
        =end
      RUBY

      assert_comment source, :embdoc, [0, 20, 1, 3, 0, 0]
    end

    def test_comment_embedded_document_with_content_on_same_line
      source = <<~RUBY
        =begin other stuff
        =end
      RUBY

      assert_comment source, :embdoc, [0, 24, 1, 2, 0, 0]
    end

    def test_attaching_comments
      source = <<~RUBY
        # Foo class
        class Foo
          # bar method
          def bar
            # baz invocation
            baz
          end # bar end
        end # Foo end
      RUBY

      result = Prism.parse(source)
      result.attach_comments!
      tree = result.value
      class_node = tree.statements.body.first
      method_node = class_node.body.body.first
      call_node = method_node.body.body.first

      assert_equal("# Foo class\n# Foo end", class_node.location.comments.map { |c| c.location.slice }.join("\n"))
      assert_equal("# bar method\n# bar end", method_node.location.comments.map { |c| c.location.slice }.join("\n"))
      assert_equal("# baz invocation", call_node.location.comments.map { |c| c.location.slice }.join("\n"))
    end

    private

    def assert_comment(source, type, locations)
      start_offset, end_offset, start_line, end_line, start_column, end_column = locations
      expected = {
        start_offset: start_offset,
        end_offset: end_offset,
        start_line: start_line,
        end_line: end_line,
        start_column: start_column,
        end_column: end_column
      }

      result = Prism.parse(source)
      assert result.errors.empty?, result.errors.map(&:message).join("\n")
      assert_equal type, result.comments.first.type

      first_comment_location = result.comments.first.location

      actual = {
        start_offset: first_comment_location.start_offset,
        end_offset: first_comment_location.end_offset,
        start_line: first_comment_location.start_line,
        end_line: first_comment_location.end_line,
        start_column: first_comment_location.start_column,
        end_column: first_comment_location.end_column
      }

      assert_equal expected, actual
    end
  end
end
