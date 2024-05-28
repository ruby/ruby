# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class CommentsTest < TestCase
    def test_comment_inline
      source = "# comment"
      assert_equal [0], Prism.parse(source).source.offsets

      assert_comment(
        source,
        InlineComment,
        start_offset: 0,
        end_offset: 9,
        start_line: 1,
        end_line: 1,
        start_column: 0,
        end_column: 9
      )
    end

    def test_comment_inline_def
      source = <<~RUBY
      def foo
        # a comment
      end
      RUBY

      assert_comment(
        source,
        InlineComment,
        start_offset: 10,
        end_offset: 21,
        start_line: 2,
        end_line: 2,
        start_column: 2,
        end_column: 13
      )
    end

    def test___END__
      result = Prism.parse(<<~RUBY)
        __END__
        comment
      RUBY

      data_loc = result.data_loc
      assert_equal 0, data_loc.start_offset
      assert_equal 16, data_loc.end_offset
    end

    def test___END__crlf
      result = Prism.parse("__END__\r\ncomment\r\n")

      data_loc = result.data_loc
      assert_equal 0, data_loc.start_offset
      assert_equal 18, data_loc.end_offset
    end

    def test_comment_embedded_document
      source = <<~RUBY
        =begin
        comment
        =end
      RUBY

      assert_comment(
        source,
        EmbDocComment,
        start_offset: 0,
        end_offset: 20,
        start_line: 1,
        end_line: 4,
        start_column: 0,
        end_column: 0
      )
    end

    def test_comment_embedded_document_with_content_on_same_line
      source = <<~RUBY
        =begin other stuff
        =end
      RUBY

      assert_comment(
        source,
        EmbDocComment,
        start_offset: 0,
        end_offset: 24,
        start_line: 1,
        end_line: 3,
        start_column: 0,
        end_column: 0
      )
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

    def assert_comment(source, type, start_offset:, end_offset:, start_line:, end_line:, start_column:, end_column:)
      result = Prism.parse(source)
      assert result.errors.empty?, result.errors.map(&:message).join("\n")
      assert_kind_of type, result.comments.first

      location = result.comments.first.location
      assert_equal start_offset, location.start_offset, -> { "Expected start_offset to be #{start_offset}" }
      assert_equal end_offset, location.end_offset, -> { "Expected end_offset to be #{end_offset}" }
      assert_equal start_line, location.start_line, -> { "Expected start_line to be #{start_line}" }
      assert_equal end_line, location.end_line, -> { "Expected end_line to be #{end_line}" }
      assert_equal start_column, location.start_column, -> { "Expected start_column to be #{start_column}" }
      assert_equal end_column, location.end_column, -> { "Expected end_column to be #{end_column}" }
    end
  end
end
