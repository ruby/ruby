# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
  class HeredocTest < TestCase
    def test_word_separators_spanning_a_heredoc
      %w[%w %i].each do |literal|
        { "\nA\n " => [], "first\nbody\nA\n  second" => %w[first second] }.each do |contents, expected|
          source = "[<<A, #{literal}[#{contents}]]"
          result = Ruby::Prism.parse(source)

          assert_empty result.errors, source
          assert_equal expected, result.statement.elements.last.elements.map(&:unescaped), source
        end
      end
    end

    def test_long_heredoc_terminator
      [17, 32, 77].each do |length|
        terminator = "A" * length
        body = +""
        length.times do |index|
          line = terminator.dup
          line[index] = "B"
          body << line << "\n"
        end

        assert_equal body, Ruby::Prism.parse_statement("<<#{terminator}\n#{body}#{terminator}\n").unescaped
      end
    end

    def test_heredoc?
      refute Ruby::Prism.parse_statement("\"foo\"").heredoc?
      refute Ruby::Prism.parse_statement("\"foo \#{1}\"").heredoc?
      refute Ruby::Prism.parse_statement("`foo`").heredoc?
      refute Ruby::Prism.parse_statement("`foo \#{1}`").heredoc?

      assert Ruby::Prism.parse_statement("<<~HERE\nfoo\nHERE\n").heredoc?
      assert Ruby::Prism.parse_statement("<<~HERE\nfoo \#{1}\nHERE\n").heredoc?
      assert Ruby::Prism.parse_statement("<<~`HERE`\nfoo\nHERE\n").heredoc?
      assert Ruby::Prism.parse_statement("<<~`HERE`\nfoo \#{1}\nHERE\n").heredoc?
    end
  end
end
