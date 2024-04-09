# frozen_string_literal: true

return if RUBY_VERSION < "3.1"

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
      assert_warning("if a = 1; end; a", "should be ==")
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
      assert_warning("1 if 2..foo", "integer")
    end

    def test_keyword_eol
      assert_warning("if\ntrue; end", "end of line")
      assert_warning("if true\nelsif\nfalse; end", "end of line")
    end

    def test_string_in_predicate
      assert_warning("if 'foo'; end", "string")
      assert_warning("if \"\#{foo}\"; end", "string")
      assert_warning("if __FILE__; end", "string")
    end

    def test_symbol_in_predicate
      assert_warning("if :foo; end", "symbol")
      assert_warning("if :\"\#{foo}\"; end", "symbol")
    end

    def test_literal_in_predicate
      assert_warning("if __LINE__; end", "literal")
      assert_warning("if __ENCODING__; end", "literal")
      assert_warning("if 1; end", "literal")
      assert_warning("if 1.0; end", "literal")
      assert_warning("if 1r; end", "literal")
      assert_warning("if 1i; end", "literal")
    end

    def test_regexp_in_predicate
      assert_warning("if /foo/; end", "regex")
      assert_warning("if /foo\#{bar}/; end", "regex")
    end

    def test_unused_local_variables
      assert_warning("foo = 1", "unused")

      refute_warning("foo = 1", compare: false, command_line: "e")
      refute_warning("foo = 1", compare: false, scopes: [[]])

      assert_warning("def foo; bar = 1; end", "unused")
      assert_warning("def foo; bar, = 1; end", "unused")

      refute_warning("def foo; bar &&= 1; end")
      refute_warning("def foo; bar ||= 1; end")
      refute_warning("def foo; bar += 1; end")

      refute_warning("def foo; bar = bar; end")
      refute_warning("def foo; bar = bar = 1; end")
      refute_warning("def foo; bar = (bar = 1); end")
      refute_warning("def foo; bar = begin; bar = 1; end; end")
      refute_warning("def foo; bar = (qux; bar = 1); end")
      refute_warning("def foo; bar, = bar = 1; end")
      refute_warning("def foo; bar, = 1, bar = 1; end")

      refute_warning("def foo(bar); end")
      refute_warning("def foo(bar = 1); end")
      refute_warning("def foo((bar)); end")
      refute_warning("def foo(*bar); end")
      refute_warning("def foo(*, bar); end")
      refute_warning("def foo(*, (bar)); end")
      refute_warning("def foo(bar:); end")
      refute_warning("def foo(**bar); end")
      refute_warning("def foo(&bar); end")
      refute_warning("->(bar) {}")
      refute_warning("->(; bar) {}", compare: false)

      refute_warning("def foo; bar = 1; tap { bar }; end")
      refute_warning("def foo; bar = 1; tap { baz = bar; baz }; end")
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

    def refute_warning(source, compare: true, **options)
      assert_empty Prism.parse(source, **options).warnings

      if compare && defined?(RubyVM::AbstractSyntaxTree)
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
