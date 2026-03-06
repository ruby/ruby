# frozen_string_literal: true

return if !(RUBY_ENGINE == "ruby" && RUBY_VERSION >= "3.2.0")

require_relative "test_helper"
require "ripper"

module Prism
  class LexTest < TestCase
    def test_lex_file
      assert_nothing_raised do
        Prism.lex_file(__FILE__)
      end

      error = assert_raise Errno::ENOENT do
        Prism.lex_file("idontexist.rb")
      end

      assert_equal "No such file or directory - idontexist.rb", error.message

      assert_raise TypeError do
        Prism.lex_file(nil)
      end
    end

    def test_parse_lex
      node, tokens = Prism.parse_lex("def foo; end").value

      assert_kind_of ProgramNode, node
      assert_equal 5, tokens.length
    end

    def test_parse_lex_file
      node, tokens = Prism.parse_lex_file(__FILE__).value

      assert_kind_of ProgramNode, node
      refute_empty tokens

      error = assert_raise Errno::ENOENT do
        Prism.parse_lex_file("idontexist.rb")
      end

      assert_equal "No such file or directory - idontexist.rb", error.message

      assert_raise TypeError do
        Prism.parse_lex_file(nil)
      end
    end

    if RUBY_VERSION >= "3.3"
      def test_lex_compat
        source = "foo bar"
        prism = Prism.lex_compat(source, version: "current").value
        ripper = Ripper.lex(source)
        assert_equal(ripper, prism)
      end
    end

    def test_lex_interpolation_unterminated
      assert_equal(
        %i[STRING_BEGIN EMBEXPR_BEGIN EOF],
        token_types('"#{')
      )

      assert_equal(
        %i[STRING_BEGIN EMBEXPR_BEGIN IGNORED_NEWLINE EOF],
        token_types('"#{' + "\n")
      )
    end

    def test_lex_interpolation_unterminated_with_content
      # FIXME: Emits EOL twice.
      assert_equal(
        %i[STRING_BEGIN EMBEXPR_BEGIN CONSTANT EOF EOF],
        token_types('"#{C')
      )

      assert_equal(
        %i[STRING_BEGIN EMBEXPR_BEGIN CONSTANT NEWLINE EOF],
        token_types('"#{C' + "\n")
      )
    end

    def test_lex_heredoc_unterminated
      code = <<~'RUBY'.strip
        <<A+B
        #{C
      RUBY

      assert_equal(
        %i[HEREDOC_START EMBEXPR_BEGIN CONSTANT HEREDOC_END PLUS CONSTANT NEWLINE EOF],
        token_types(code)
      )

      assert_equal(
        %i[HEREDOC_START EMBEXPR_BEGIN CONSTANT NEWLINE HEREDOC_END PLUS CONSTANT NEWLINE EOF],
        token_types(code + "\n")
      )
    end

    def token_types(code)
      Prism.lex(code).value.map { |token, _state| token.type }
    end
  end
end
