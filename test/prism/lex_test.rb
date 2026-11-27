# frozen_string_literal: true

return if !(RUBY_ENGINE == "ruby" && RUBY_VERSION >= "3.2.0")

require_relative "test_helper"
require "ripper"

module Ruby::Prism
  class LexTest < TestCase
    def test_lex_file
      assert_nothing_raised do
        Ruby::Prism.lex_file(__FILE__)
      end

      error = assert_raise Errno::ENOENT do
        Ruby::Prism.lex_file("idontexist.rb")
      end

      assert_equal "No such file or directory - idontexist.rb", error.message

      assert_raise TypeError do
        Ruby::Prism.lex_file(nil)
      end
    end

    def test_parse_lex
      node, tokens = Ruby::Prism.parse_lex("def foo; end").value

      assert_kind_of ProgramNode, node
      assert_equal 5, tokens.length
    end

    def test_carriage_return_before_crlf_in_call_chain
      result = Ruby::Prism.lex("r\r\r\n.O")

      assert_empty result.errors
      assert_equal %i[IDENTIFIER IGNORED_NEWLINE DOT CONSTANT EOF], result.value.map(&:type)
      assert_equal "\r\n", result.value[1].value
    end

    def test_modifier_after_symbol_in_undef_and_alias
      {
        "undef:f while:c" => :KEYWORD_WHILE_MODIFIER,
        "undef f, :+ until:c" => :KEYWORD_UNTIL_MODIFIER,
        "alias :new :old if:c" => :KEYWORD_IF_MODIFIER
      }.each do |source, modifier|
        result = Ruby::Prism.lex(source)
        assert_empty result.errors, source
        assert_include result.value.map(&:type), modifier, source
      end
    end

    def test_forwarding_parameter_in_a_nested_method_definition
      [
        "def outer value = def inner...\nend, range = 1...2\nend",
        "def outer(value: [def self.inner...; end, 1...2]); end"
      ].each do |source|
        result = Ruby::Prism.lex(source)
        assert_empty result.errors, source
        ellipses = result.value.select { |token| token.value == "..." }
        assert_equal %i[UDOT_DOT_DOT DOT_DOT_DOT], ellipses.map(&:type), source
      end
    end

    def test_do_after_a_command_with_a_brace_block
      {
        "outer def f = super A::B() {} do end" => :KEYWORD_DO_BLOCK,
        "outer def f = super A::B {} rescue fallback do end" => :KEYWORD_DO,
        "outer inner f (x) {} do end" => :KEYWORD_DO_BLOCK,
        "outer inner super super A::B { other super B::C {} } do end" => :KEYWORD_DO_BLOCK,
        "while super A::B {} do end" => :KEYWORD_DO_LOOP
      }.each do |source, expected|
        tokens = Ruby::Prism.lex(source, version: "4.0").value
        assert_equal [expected], tokens.select { |token| token.value == "do" }.map(&:type), source
      end
    end

    def test_parse_lex_file
      node, tokens = Ruby::Prism.parse_lex_file(__FILE__).value

      assert_kind_of ProgramNode, node
      refute_empty tokens

      error = assert_raise Errno::ENOENT do
        Ruby::Prism.parse_lex_file("idontexist.rb")
      end

      assert_equal "No such file or directory - idontexist.rb", error.message

      assert_raise TypeError do
        Ruby::Prism.parse_lex_file(nil)
      end
    end

    def test_lex_encoding
      tokens = Ruby::Prism.lex('"わたし"', encoding: Encoding::Windows_31J).value
      tokens.each do |t|
        assert_equal(Encoding::Windows_31J, t.value.encoding)
      end

      # Shebangs must appear on the first line. For these cases, the encoding
      # comment may appear second, but it should still change encoding.
      tokens = Ruby::Prism.lex(<<~RUBY, encoding: Encoding::Windows_31J).value
        #! /usr/bin/env ruby
        # encoding: utf-8
        "わたし"
      RUBY
      tokens.each do |t|
        assert_equal(Encoding::UTF_8, t.value.encoding)
      end
    end

    def test_lex_legacy
      tokens = Ruby::Prism.lex("foo").value

      tokens.each do |token, state|
        assert_nil(state)
        assert_equal(token, token[0])
        assert(token[1])
        assert_equal(token, token.first)
      end
    end

    if RUBY_VERSION >= "3.3"
      def test_lex_compat
        source = "foo bar"
        prism = Ruby::Prism.lex_compat(source, version: "current").value
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

    def test_lex_identifier_underscore_caret
      assert_equal(
        %i[IDENTIFIER CARET IDENTIFIER EOF],
        token_types("foo____^bar")
      )

      assert_equal(
        %i[IDENTIFIER CARET IDENTIFIER EOF],
        token_types("a_1234_^b")
      )
    end

    def test_missing_operand_after_identifier_ending_in_underscore
      # Move the caret through two 8-byte SWAR words. The second array element
      # leaves a full word to scan even when the identifier is short.
      16.times do |length|
        source = "[#{"a" * length}_^, another_value]"
        assert_equal [:expect_expression_after_operator], Ruby::Prism.lex(source).errors.map(&:type), source
      end
    end

    def token_types(code)
      Ruby::Prism.lex(code).value.map(&:type)
    end
  end
end
