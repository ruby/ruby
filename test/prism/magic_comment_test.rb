# frozen_string_literal: true

require_relative "test_helper"

module Prism
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

    def test_coding_whitespace
      assert_magic_encoding(Encoding::ASCII_8BIT, "# coding \t \r  \v   :     \t \v    \r   ascii-8bit")
    end

    def test_vim
      assert_magic_encoding(Encoding::Windows_31J, "# vim: filetype=ruby, fileencoding=windows-31j, tabsize=3, shiftwidth=3")
    end

    private

    def assert_magic_encoding(expected, line)
      source = %Q{#{line}\n""}
      actual = Prism.parse(source).encoding

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
      actual = Prism.parse(source).magic_comments

      assert_equal expected.length, actual.length
      expected.zip(actual).each do |(expected_key, expected_value), magic_comment|
        assert_equal expected_key, magic_comment.key
        assert_equal expected_value, magic_comment.value
      end
    end
  end
end
