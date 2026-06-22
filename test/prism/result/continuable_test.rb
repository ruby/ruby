# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class ContinuableTest < TestCase
    def test_valid_input
      # Valid input is not continuable (nothing to continue).
      refute_predicate Prism.parse("1 + 1"), :continuable?
      refute_predicate Prism.parse(""), :continuable?
    end

    def test_stray_closing_tokens
      # Stray closing tokens make input non-continuable regardless of what
      # follows (matches the feature-request examples exactly).
      refute_predicate Prism.parse("1 + ]"), :continuable?
      refute_predicate Prism.parse("end.tap do"), :continuable?

      # A mix: stray end plus an unclosed block is not continuable because the
      # stray end cannot be fixed by appending more input.
      refute_predicate Prism.parse("end\ntap do"), :continuable?
    end

    def test_unclosed_constructs
      # Unclosed constructs are continuable.
      assert_predicate Prism.parse("1 + ["), :continuable?
      assert_predicate Prism.parse("tap do"), :continuable?
    end

    def test_unclosed_keywords
      assert_predicate Prism.parse("def foo"), :continuable?
      assert_predicate Prism.parse("class Foo"), :continuable?
      assert_predicate Prism.parse("module Foo"), :continuable?
      assert_predicate Prism.parse("if true"), :continuable?
      assert_predicate Prism.parse("while true"), :continuable?
      assert_predicate Prism.parse("begin"), :continuable?
      assert_predicate Prism.parse("for x in [1]"), :continuable?
    end

    def test_unclosed_delimiters
      assert_predicate Prism.parse("{"), :continuable?
      assert_predicate Prism.parse("foo("), :continuable?
      assert_predicate Prism.parse('"hello'), :continuable?
      assert_predicate Prism.parse("'hello"), :continuable?
      assert_predicate Prism.parse("<<~HEREDOC\nhello"), :continuable?
    end

    def test_trailing_whitespace
      # Trailing whitespace or newlines should not affect continuability.
      assert_predicate Prism.parse("class A\n"), :continuable?
      assert_predicate Prism.parse("def f "), :continuable?
      assert_predicate Prism.parse("def f\n"), :continuable?
      assert_predicate Prism.parse("def f\n  "), :continuable?
      assert_predicate Prism.parse("( "), :continuable?
      assert_predicate Prism.parse("(\n"), :continuable?
      assert_predicate Prism.parse("1 +\n"), :continuable?
    end

    def test_incomplete_expressions
      assert_predicate Prism.parse("-"), :continuable?
      assert_predicate Prism.parse("[1,"), :continuable?
      assert_predicate Prism.parse("f arg1,"), :continuable?
      assert_predicate Prism.parse("def f ="), :continuable?
      assert_predicate Prism.parse("def $a"), :continuable?
      assert_predicate Prism.parse("a ="), :continuable?
      assert_predicate Prism.parse("a,b"), :continuable?
    end

    def test_modifier_keywords
      assert_predicate Prism.parse("return if"), :continuable?
      assert_predicate Prism.parse("return unless"), :continuable?
      assert_predicate Prism.parse("while"), :continuable?
      assert_predicate Prism.parse("until"), :continuable?
    end

    def test_ternary_operator
      assert_predicate Prism.parse("x ?"), :continuable?
      assert_predicate Prism.parse("x ? y :"), :continuable?
    end

    def test_class_with_superclass
      assert_predicate Prism.parse("class Foo <"), :continuable?
    end

    def test_keyword_expressions
      assert_predicate Prism.parse("not"), :continuable?
      assert_predicate Prism.parse("defined?"), :continuable?
      assert_predicate Prism.parse("module"), :continuable?
    end

    def test_for_loops
      assert_predicate Prism.parse("for"), :continuable?
      assert_predicate Prism.parse("for x in"), :continuable?
    end

    def test_pattern_matching
      assert_predicate Prism.parse("foo => ["), :continuable?
      assert_predicate Prism.parse("case foo; when"), :continuable?
    end

    def test_splat_and_block_pass
      assert_predicate Prism.parse("[*"), :continuable?
      assert_predicate Prism.parse("f(**"), :continuable?
      assert_predicate Prism.parse("f(&"), :continuable?
    end

    def test_default_parameter_value
      assert_predicate Prism.parse("def f(x ="), :continuable?
    end

    def test_line_continuation
      assert_predicate Prism.parse("1 +\\"), :continuable?
      assert_predicate Prism.parse("\"foo\" \\"), :continuable?
    end

    def test_embedded_document
      # Embedded document (=begin) truncated at various points.
      assert_predicate Prism.parse("=b"), :continuable?
      assert_predicate Prism.parse("=beg"), :continuable?
      assert_predicate Prism.parse("=begin"), :continuable?
      assert_predicate Prism.parse("foo\n=b"), :continuable?
    end
  end
end
