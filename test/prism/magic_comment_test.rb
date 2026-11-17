# frozen_string_literal: true

require_relative "test_helper"
require "ripper"

module Ruby::Prism
  class MagicCommentTest < TestCase
    if RUBY_ENGINE == "ruby"
      class MagicCommentRipper < Ripper
        attr_reader :magic_comments

        def initialize(*)
          super
          @magic_comments = []
        end

        def on_magic_comment(key, value)
          @magic_comments << [key, value]
          super
        end
      end

      Fixture.each do |fixture|
        define_method(fixture.test_name) { assert_magic_comments(fixture) }
      end
    end

    def test_encoding
      assert_magic_encoding(Encoding::US_ASCII, "# encoding: ascii")
    end

    def test_coding
      assert_magic_encoding(Encoding::US_ASCII, "# coding: ascii")
    end

    def test_eNcOdInG
      assert_magic_encoding(Encoding::US_ASCII, "# eNcOdInG: ascii")
    end

    def test_CoDiNg
      assert_magic_encoding(Encoding::US_ASCII, "# CoDiNg: ascii")
    end

    def test_encoding_whitespace
      assert_magic_encoding(Encoding::US_ASCII, "# \s\t\v encoding \s\t\v : \s\t\v ascii \s\t\v")
    end

    def test_emacs_encoding
      assert_magic_encoding(Encoding::US_ASCII, "# -*- encoding: ascii -*-")
    end

    def test_emacs_coding
      assert_magic_encoding(Encoding::US_ASCII, "# -*- coding: ascii -*-")
    end

    def test_emacs_eNcOdInG
      assert_magic_encoding(Encoding::US_ASCII, "# -*- eNcOdInG: ascii -*-")
    end

    def test_emacs_CoDiNg
      assert_magic_encoding(Encoding::US_ASCII, "# -*- CoDiNg: ascii -*-")
    end

    def test_emacs_whitespace
      assert_magic_encoding(Encoding::US_ASCII, "# -*- \s\t\v encoding \s\t\v : \s\t\v ascii \s\t\v -*-")
    end

    def test_emacs_multiple
      assert_magic_encoding(Encoding::US_ASCII, "# -*- foo: bar; encoding: ascii -*-")
    end

    def test_emacs_missing_delimiter
      assert_magic_encoding(Encoding::US_ASCII, '# -*- \1; encoding: ascii -*-')
    end

    def test_coding_whitespace
      assert_magic_encoding(Encoding::ASCII_8BIT, "# coding \t \r  \v   :     \t \v    \r   ascii-8bit")
    end

    def test_vim
      assert_magic_encoding(Encoding::Windows_31J, "# vim: filetype=ruby, fileencoding=windows-31j, tabsize=3, shiftwidth=3")
    end

    def test_nul_in_magic_comment_values
      {
        "frozen_string_literal" => ["true", "false"],
        "warn_indent" => ["true", "false"],
        "shareable_constant_value" => ["none", "literal", "experimental_everything", "experimental_copy"]
      }.each do |key, values|
        values.each do |value|
          value.length.times do |index|
            invalid = value.dup
            invalid[index] = "\0"
            result = Ruby::Prism.parse("# #{key}: #{invalid}\n")

            assert_predicate result, :success?
            assert_equal [:invalid_magic_comment_value], result.warnings.map(&:type), "#{key}: #{invalid.inspect}"
          end
        end
      end
    end

    def test_nul_value_preserves_frozen_string_literal_option
      [false, true].each do |frozen|
        result = Ruby::Prism.parse("# frozen_string_literal: \0abc\n\"a\"", frozen_string_literal: frozen)
        assert_equal frozen, result.value.statements.body.first.frozen?
        assert_include result.warnings.map(&:type), :invalid_magic_comment_value
      end
    end

    def test_invalid_encoding_value_does_not_fall_back_to_prefix
      ["coding", "encoding"].each do |key|
        ["Windows-31J[", "ascii!", "binary?", "unknown"].each do |value|
          ["# #{key}: #{value}", "# #{key}: \"#{value}\"", "# -*- #{key}: #{value} -*-"].each do |comment|
            result = Ruby::Prism.parse("#{comment}\n__ENCODING__")

            assert_equal [:invalid_encoding_magic_comment], result.errors.map(&:type)
            assert_equal value, result.errors.first.location.slice
            assert_equal Encoding::UTF_8, result.encoding
          end
        end
      end
    end

    def test_encoding_fallback_is_not_used_for_unrecognized_keys
      ['#"ncoding:binary', "#'ncoding:binary", "#;ncoding:binary", "# coding=binary", "# coding=e", "# -*- coding=binary -*-"].each do |comment|
        result = Ruby::Prism.parse("#{comment}\n__ENCODING__")

        assert_predicate result, :success?, comment
        assert_equal Encoding::UTF_8, result.encoding, comment
      end
    end

    def test_encoding_after_leading_delimiters
      ['"', "'", ";", ":"].each do |delimiter|
        ["coding", "encoding"].each do |key|
          result = Ruby::Prism.parse("##{delimiter}#{key}:binary\n__ENCODING__")
          assert_predicate result, :success?
          assert_equal Encoding::ASCII_8BIT, result.encoding
        end
      end
    end

    def test_encoding_after_non_ruby_shebang
      ["#!/bin/sh", "#!", "#!coding:;"].each do |shebang|
        ["\n", "\r\n"].each do |newline|
          source = "#{shebang}#{newline}  # encoding: US-ASCII#{newline}__ENCODING__"
          result = Ruby::Prism.parse(source)

          assert_predicate result, :success?
          assert_equal Encoding::US_ASCII, result.encoding
        end
      end
    end

    def test_shebang_is_not_an_encoding_comment
      ["#!coding:bogus", "#!ruby coding:bogus"].each do |shebang|
        ["", "\n"].each do |newline|
          result = Ruby::Prism.parse("#{shebang}#{newline}")

          assert_predicate result, :success?
          assert_equal Encoding::UTF_8, result.encoding
        end
      end
    end

    def test_encoding_after_searched_shebang
      source = "#!/bin/sh\n# encoding: US-ASCII\n#!ruby\n# encoding: binary\n__ENCODING__"
      [{ main_script: true }, { command_line: "x" }].each do |options|
        result = Ruby::Prism.parse(source, **options)

        assert_predicate result, :success?
        assert_equal Encoding::ASCII_8BIT, result.encoding
      end
    end

    private

    def assert_magic_encoding(expected, line)
      source = %Q{#{line}\n""}
      actual = Ruby::Prism.parse(source).encoding

      # Compare against our expectation.
      assert_equal expected, actual

      # Compare against Ruby's expectation.
      if defined?(RubyVM::InstructionSequence)
        previous = $VERBOSE
        expected =
          begin
            $VERBOSE = nil
            RubyVM::InstructionSequence.compile(source).eval.encoding
          ensure
            $VERBOSE = previous
          end
        assert_equal expected, actual
      end
    end

    def assert_magic_comments(fixture)
      source = fixture.read

      # Check that we get the correct number of magic comments when lexing with
      # ripper.
      expected = MagicCommentRipper.new(source).tap(&:parse).magic_comments
      actual = Ruby::Prism.parse(source).magic_comments

      assert_equal expected.length, actual.length
      expected.zip(actual).each do |(expected_key, expected_value), magic_comment|
        assert_equal expected_key, magic_comment.key
        assert_equal expected_value, magic_comment.value
      end
    end
  end
end
