# frozen_string_literal: true

require_relative "test_helper"

module Ruby::Prism
  # When an escape sequence consumes the newline of a line whose heredoc body
  # has already been lexed, the content continues after that body.
  class HeredocEscapedNewlineTest < TestCase
    ESCAPES = { "\\\n" => "", "\\c\n" => "\n", "\\C-\n" => "\n", "\\M-\n" => "\x8A".b, "\\M-\\C-\n" => "\x8A".b }

    # Lists and character literals keep an escaped newline as a newline.
    LITERAL_ESCAPES = ESCAPES.merge("\\\n" => "\n")

    def test_string
      ESCAPES.each do |escape, value|
        assert_content("body\n#{value}rest".b, "\"\#{<<A}#{escape}body\nA\nrest\"\n")
      end
    end

    def test_percent_string
      ESCAPES.each do |escape, value|
        assert_content("body\n#{value}rest".b, "%Q(\#{<<A}#{escape}body\nA\nrest)\n")
      end
    end

    def test_list
      LITERAL_ESCAPES.each do |escape, value|
        assert_content(["body\n#{value}rest".b], "%W[\#{<<A}#{escape}body\nA\nrest]\n")
      end
    end

    def test_heredoc
      ESCAPES.each do |escape, value|
        assert_content("body\n#{value}rest\n".b, "<<B\n\#{<<A}#{escape}body\nA\nrest\nB\n")
      end
    end

    def test_heredoc_continued_line_is_not_terminator
      ESCAPES.each do |escape, value|
        assert_content("body\n#{value}B\nrest\n".b, "<<B\n\#{<<A}#{escape}body\nA\nB\nrest\nB\n")
      end
    end

    def test_dedenting_heredoc_continued_line_is_not_terminator
      ESCAPES.each do |escape, value|
        assert_content("  body\n#{value}B\nrest\n".b, "<<~B\n  \#{<<A}#{escape}body\nA\nB\nrest\nB\n")
      end
    end

    def test_char_literal
      LITERAL_ESCAPES.each do |escape, value|
        assert_content(["body\n".b, value.b], "[<<A, ?#{escape}body\nA\n]\n")
      end
    end

    def test_regular_expression
      assert_content("body\n\\x0Arest".b, "/\#{<<A}\\C-\nbody\nA\nrest/\n")
    end

    private

    def assert_content(expected, source)
      result = Ruby::Prism.parse(source)
      assert_empty result.errors, source.inspect
      assert_equal expected, content(result.value.statements.body.first), source.inspect
    end

    def content(node)
      case node
      when StringNode, RegularExpressionNode
        node.unescaped.b
      when InterpolatedStringNode, InterpolatedRegularExpressionNode
        node.parts.map { |part| content(part) }.join.b
      when EmbeddedStatementsNode
        content(node.statements.body.last)
      when ArrayNode
        node.elements.map { |element| content(element) }
      else
        raise "unexpected node: #{node.class}"
      end
    end
  end
end
