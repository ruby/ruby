# frozen_string_literal: true

require_relative "test_helper"

module YARP
  class CommentsTest < TestCase
    def test_comment_inline
      source = "# comment"

      assert_comment source, :inline, 0..9
      assert_equal [0], Debug.newlines(source)
    end

    def test_comment_inline_def
      source = <<~RUBY
      def foo
        # a comment
      end
      RUBY

      assert_comment source, :inline, 10..22
    end

    def test_comment___END__
      source = <<~RUBY
        __END__
        comment
      RUBY

      assert_comment source, :__END__, 0..16
    end

    def test_comment___END__crlf
      source = "__END__\r\ncomment\r\n"

      assert_comment source, :__END__, 0..18
    end

    def test_comment_embedded_document
      source = <<~RUBY
        =begin
        comment
        =end
      RUBY

      assert_comment source, :embdoc, 0..20
    end

    def test_comment_embedded_document_with_content_on_same_line
      source = <<~RUBY
        =begin other stuff
        =end
      RUBY

      assert_comment source, :embdoc, 0..24
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

      result = YARP.parse(source)
      result.attach_comments!
      tree = result.value
      class_node = tree.statements.body.first
      method_node = class_node.body.body.first
      call_node = method_node.body.body.first

      assert_equal("# Foo class\n# Foo end\n", class_node.location.comments.map { |c| c.location.slice }.join)
      assert_equal("# bar method\n# bar end\n", method_node.location.comments.map { |c| c.location.slice }.join)
      assert_equal("# baz invocation\n", call_node.location.comments.map { |c| c.location.slice }.join)
    end

    private

    def assert_comment(source, type, location)
      result = YARP.parse(source)
      assert result.errors.empty?, result.errors.map(&:message).join("\n")
      assert_equal result.comments.first.type, type
      assert_equal result.comments.first.location.start_offset, location.begin
      assert_equal result.comments.first.location.end_offset, location.end
    end
  end
end
