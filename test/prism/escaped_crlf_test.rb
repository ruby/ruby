# frozen_string_literal: true

require_relative "test_helper"

module Ruby::Prism
  # A control or meta escape applied to a line ending reads \r\n as one newline.
  class EscapedCRLFTest < TestCase
    ESCAPES = { "\\c" => "\n", "\\C-" => "\n", "\\M-" => "\x8A".b, "\\M-\\C-" => "\x8A".b, "\\C-\\M-" => "\x8A".b }

    def test_string
      ESCAPES.each do |escape, value|
        assert_content("a#{value}rest".b, "\"a#{escape}\r\nrest\"\r\n")
      end
    end

    def test_percent_string
      ESCAPES.each do |escape, value|
        assert_content("a#{value}rest".b, "%Q(a#{escape}\r\nrest)\r\n")
      end
    end

    def test_list
      ESCAPES.each do |escape, value|
        assert_content(["a#{value}rest".b], "%W[a#{escape}\r\nrest]\r\n")
      end
    end

    def test_heredoc
      ESCAPES.each do |escape, value|
        assert_content("a#{value}rest\n".b, "<<H\r\na#{escape}\r\nrest\r\nH\r\n")
      end
    end

    def test_dedenting_heredoc
      ESCAPES.each do |escape, value|
        assert_content("a#{value}    rest\nmore\n".b, "<<~H\r\n  a#{escape}\r\n    rest\r\n  more\r\nH\r\n")
      end
    end

    def test_char_literal
      ESCAPES.each do |escape, value|
        assert_content(value.b, "?#{escape}\r\n")
      end
    end

    def test_regular_expression
      assert_content("a\\x0Arest".b, "/a\\C-\r\nrest/\r\n")
    end

    def test_carriage_return_without_newline
      assert_content("a\rrest".b, "\"a\\C-\rrest\"\n")
      assert_content("a\x8Drest".b, "\"a\\M-\rrest\"\n")
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
      when InterpolatedStringNode
        node.parts.map { |part| content(part) }.join.b
      when ArrayNode
        node.elements.map { |element| content(element) }
      else
        raise "unexpected node: #{node.class}"
      end
    end
  end
end
