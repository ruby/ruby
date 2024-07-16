# frozen_string_literal: true

return if RUBY_VERSION < "3.1"

require_relative "../test_helper"

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

    def test_binary_operator
      [
        [:**, "argument prefix"],
        [:*, "argument prefix"],
        [:<<, "here document"],
        [:&, "argument prefix"],
        [:+, "unary operator"],
        [:-, "unary operator"],
        [:/, "regexp literal"],
        [:%, "string literal"]
      ].each do |(operator, warning)|
        assert_warning("puts 1 #{operator}0", warning)
        assert_warning("puts :a #{operator}0", warning)
        assert_warning("m = 1; puts m #{operator}0", warning)
      end
    end

    def test_equal_in_conditional
      assert_warning("if a = 1; end; a = a", "should be ==")
    end

    def test_dot_dot_dot_eol
      assert_warning("_ = foo...", "... at EOL")
      assert_warning("def foo(...) = bar ...", "... at EOL")

      assert_warning("_ = foo... #", "... at EOL")
      assert_warning("_ = foo... \t\v\f\n", "... at EOL")

      refute_warning("p foo...bar")
      refute_warning("p foo...      bar")
    end

    def test_END_in_method
      assert_warning("def foo; END {}; end", "END in method")
    end

    def test_duplicated_hash_key
      assert_warning("{ a: 1, a: 2 }", "duplicated and overwritten")
      assert_warning("{ a: 1, **{ a: 2 } }", "duplicated and overwritten")
    end

    def test_duplicated_when_clause
      assert_warning("case 1; when 1, 1; end", "when' clause")
    end

    def test_float_out_of_range
      assert_warning("_ = 1.0e100000", "out of range")
    end

    def test_integer_in_flip_flop
      assert_warning("1 if 2..foo", "integer")
    end

    def test_literal_in_conditionals
      sources = [
        "if (a = 2); a; end",
        "if ($a = 2); end",
        "if (@a = 2); end",
        "if a; elsif b = 2; b end",
        "unless (a = 2); a; end",
        "unless ($a = 2); end",
        "unless (@a = 2); end",
        "while (a = 2); a; end",
        "while ($a = 2); end",
        "while (@a = 2); end",
        "until (a = 2); a; end",
        "until ($a = 2); end",
        "until (@a = 2); end",
        "foo if (a, b = 2); [a, b]",
        "foo if a = 2 and a",
        "(@foo = 1) ? a : b",
        "!(a = 2) and a",
        "not a = 2 and a"
      ]

      if RUBY_VERSION >= "3.3"
        sources.push(
          "if (@@a = 2); end",
          "unless (@@a = 2); end",
          "while (@@a = 2); end",
          "until (@@a = 2); end"
        )
      end

      sources.each do |source|
        assert_warning(source, "= literal' in conditional, should be ==")
      end
    end

    def test_keyword_eol
      assert_warning("if\ntrue; end", "end of line")
      assert_warning("if true\nelsif\nfalse; end", "end of line")
    end

    def test_shareable_constant_value
      assert_warning("foo # shareable_constant_value: none", "ignored")
      assert_warning("\v  # shareable_constant_value: none", "ignored")

      refute_warning("# shareable_constant_value: none")
      refute_warning("    # shareable_constant_value: none")
      refute_warning("\t\t# shareable_constant_value: none")
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

    def test_void_statements
      assert_warning("foo = 1; foo", "a variable in void")
      assert_warning("@foo", "a variable in void")
      assert_warning("@@foo", "a variable in void")
      assert_warning("$foo", "a variable in void")
      assert_warning("$+", "a variable in void")
      assert_warning("$1", "a variable in void")

      assert_warning("self", "self in void")
      assert_warning("nil", "nil in void")
      assert_warning("true", "true in void")
      assert_warning("false", "false in void")

      assert_warning("1", "literal in void")
      assert_warning("1.0", "literal in void")
      assert_warning("1r", "literal in void")
      assert_warning("1i", "literal in void")
      assert_warning(":foo", "literal in void")
      assert_warning("\"foo\"", "literal in void")
      assert_warning("\"foo\#{1}\"", "literal in void")
      assert_warning("/foo/", "literal in void")
      assert_warning("/foo\#{1}/", "literal in void")

      assert_warning("Foo", "constant in void")
      assert_warning("::Foo", ":: in void")
      assert_warning("Foo::Bar", ":: in void")

      assert_warning("1..2", ".. in void")
      assert_warning("1..", ".. in void")
      assert_warning("..2", ".. in void")
      assert_warning("1...2", "... in void")
      assert_warning("1...;", "... in void")
      assert_warning("...2", "... in void")

      assert_warning("defined?(foo)", "defined? in void")

      assert_warning("1 + 1", "+ in void")
      assert_warning("1 - 1", "- in void")
      assert_warning("1 * 1", "* in void")
      assert_warning("1 / 1", "/ in void")
      assert_warning("1 % 1", "% in void")
      assert_warning("1 | 1", "| in void")
      assert_warning("1 ^ 1", "^ in void")
      assert_warning("1 & 1", "& in void")
      assert_warning("1 > 1", "> in void")
      assert_warning("1 < 1", "< in void")

      assert_warning("1 ** 1", "** in void")
      assert_warning("1 <= 1", "<= in void")
      assert_warning("1 >= 1", ">= in void")
      assert_warning("1 != 1", "!= in void")
      assert_warning("1 == 1", "== in void")
      assert_warning("1 <=> 1", "<=> in void")

      assert_warning("+foo", "+@ in void")
      assert_warning("-foo", "-@ in void")

      assert_warning("def foo; @bar; @baz; end", "variable in void")
      refute_warning("def foo; @bar; end")
      refute_warning("@foo", compare: false, scopes: [[]])
    end

    def test_unreachable_statement
      assert_warning("begin; rescue; retry; foo; end", "statement not reached")

      assert_warning("return; foo", "statement not reached")

      assert_warning("tap { break; foo }", "statement not reached")
      assert_warning("tap { break 1; foo }", "statement not reached")

      assert_warning("tap { next; foo }", "statement not reached")
      assert_warning("tap { next 1; foo }", "statement not reached")

      assert_warning("tap { redo; foo }", "statement not reached")
    end

    def test_warnings_verbosity
      warning = Prism.parse("def foo; END { }; end").warnings.first
      assert_equal "END in method; use at_exit", warning.message
      assert_equal :default, warning.level

      warning = Prism.parse("foo /regexp/").warnings.first
      assert_equal "ambiguous `/`; wrap regexp in parentheses or add a space after `/` operator", warning.message
      assert_equal :verbose, warning.level
    end

    private

    def assert_warning(source, message)
      warnings = Prism.parse(source).warnings

      assert_equal 1, warnings.length, "Expected only one warning in #{source.inspect}, got #{warnings.map(&:message).inspect}"
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
