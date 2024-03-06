# frozen_string_literal: true

return if RUBY_VERSION < "3.0"

require_relative "test_helper"
require "stringio"

module Prism
  class WarningsTest < TestCase
    def test_ambiguous_uminus
      assert_warning("a -b", "ambiguous first argument")
    end

    def test_ambiguous_uplus
      assert_warning("a +b", "ambiguous first argument")
    end

    def test_ambiguous_ustar
      assert_warning("a *b", "argument prefix")
    end

    def test_ambiguous_regexp
      assert_warning("a /b/", "wrap regexp in parentheses")
    end

    def test_equal_in_conditional
      assert_warning("if a = 1; end", "should be ==")
    end

    def test_dot_dot_dot_eol
      assert_warning("foo...", "... at EOL")
      assert_warning("def foo(...) = bar ...", "... at EOL")

      assert_warning("foo... #", "... at EOL")
      assert_warning("foo... \t\v\f\n", "... at EOL")

      refute_warning("p foo...bar")
      refute_warning("p foo...      bar")
    end

    def test_END_in_method
      assert_warning("def foo; END {}; end", "END in method")
    end

    def test_duplicated_hash_key
      assert_warning("{ a: 1, a: 2 }", "duplicated and overwritten")
    end

    def test_duplicated_when_clause
      assert_warning("case 1; when 1, 1; end", "clause with line")
    end

    def test_float_out_of_range
      assert_warning("1.0e100000", "out of range")
    end

    def test_integer_in_flip_flop
      assert_warning("1 if 2..3.0", "integer")
    end

    def test_keyword_eol
      assert_warning("if\ntrue; end", "end of line")
      assert_warning("if true\nelsif\nfalse; end", "end of line")
    end

    private

    def assert_warning(source, message)
      warnings = Prism.parse(source).warnings

      assert_equal 1, warnings.length
      assert_include warnings.first.message, message

      if defined?(RubyVM::AbstractSyntaxTree)
        assert_include capture_warning { RubyVM::AbstractSyntaxTree.parse(source) }, message
      end
    end

    def refute_warning(source)
      assert_empty Prism.parse(source).warnings

      if defined?(RubyVM::AbstractSyntaxTree)
        assert_empty capture_warning { RubyVM::AbstractSyntaxTree.parse(source) }
      end
    end

    def capture_warning
      stderr, $stderr, verbose, $VERBOSE = $stderr, StringIO.new, $VERBOSE, true

      begin
        yield
        $stderr.string
      ensure
        $stderr, $VERBOSE = stderr, verbose
      end
    end
  end
end
