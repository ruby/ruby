# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class HeredocDedentTest < TestCase
    def test_content_dedented_interpolation_content
      assert_heredoc_dedent(
        "  a\n" "1\n" "  a\n",
        "<<~EOF\n" "  a\n" "\#{1}\n" "  a\n" "EOF\n"
      )
    end

    def test_content
      assert_heredoc_dedent(
        "a\n",
        "<<~EOF\n" "  a\n" "EOF\n"
      )
    end

    def test_tabs_dedent_spaces
      assert_heredoc_dedent(
        "\ta\n" "b\n" "\t\tc\n",
        "<<~EOF\n" "\ta\n" "  b\n" "\t\tc\n" "EOF\n"
      )
    end

    def test_interpolation_then_content
      assert_heredoc_dedent(
        "1 a\n",
        "<<~EOF\n" "  \#{1} a\n" "EOF\n"
      )
    end

    def test_content_then_interpolation
      assert_heredoc_dedent(
        "a 1\n",
        "<<~EOF\n" "  a \#{1}\n" "EOF\n"
      )
    end

    def test_content_dedented_interpolation
      assert_heredoc_dedent(
        " a\n" "1\n",
        "<<~EOF\n" "  a\n" " \#{1}\n" "EOF\n"
      )
    end

    def test_content_interpolation
      assert_heredoc_dedent(
        "a\n" "1\n",
        "<<~EOF\n" "  a\n" "  \#{1}\n" "EOF\n"
      )
    end

    def test_content_content
      assert_heredoc_dedent(
        "a\n" "b\n",
        "<<~EOF\n" "  a\n" "  b\n" "EOF\n"
      )
    end

    def test_content_indented_content
      assert_heredoc_dedent(
        "a\n" "  b\n",
        "<<~EOF\n" "  a\n" "    b\n" "EOF\n"
      )
    end

    def test_content_dedented_content
      assert_heredoc_dedent(
        "\ta\n" "b\n",
        "<<~EOF\n" "\t\t\ta\n" "\t\tb\n" "EOF\n"
      )
    end

    def test_single_quote
      assert_heredoc_dedent(
        "a \#{1}\n",
        "<<~'EOF'\n" "a \#{1}\n" "EOF\n"
      )
    end

    def test_mixed_indentation
      assert_heredoc_dedent(
        "a\n" " b\n",
        "<<~EOF\n" "\ta\n" "\t b\n" "EOF\n"
      )
    end

    def test_indented_content_content
      assert_heredoc_dedent(
        " a\n" "b\n",
        "<<~EOF\n" "\t a\n" "\tb\n" "EOF\n"
      )
    end

    def test_indent_size
      assert_heredoc_dedent(
        "a\n" "  b\n",
        "<<~EOF\n" "\ta\n" "          b\n" "EOF\n"
      )
    end

    def test_blank_lines
      assert_heredoc_dedent(
        "a\n" "\n" "b\n",
        "<<~EOF\n" "  a\n" "\n" "  b\n" "EOF\n"
      )
    end

    def test_many_blank_lines
      assert_heredoc_dedent(
        "a\n" "\n" "\n" "\n" "\n" "b\n",
        "<<~EOF\n" "  a\n" "\n" "\n" "\n" "\n" "  b\n" "EOF\n"
      )
    end

    private

    def assert_heredoc_dedent(expected, source)
      node = Prism.parse_statement(source)

      if node.is_a?(StringNode)
        actual = node.unescaped
      else
        actual = node.parts.map { |part| part.is_a?(StringNode) ? part.unescaped : "1" }.join
      end

      assert_equal(expected, actual)
      assert_equal(eval(source), actual)
    end
  end
end
