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

    def test_ambiguous_ampersand
      assert_warning("a &b", "argument prefix")
      assert_warning("a &:+", "argument prefix")

      refute_warning("a &:b")
      refute_warning("a &:'b'")
      refute_warning("a &:\"b\"")
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

    def test_indentation_mismatch
      assert_warning("if true\n  end", "mismatched indentations at 'end' with 'if'")
      assert_warning("if true\n  elsif true\nend", "mismatched indentations at 'elsif' with 'if'")
      assert_warning("if true\n  else\nend", "mismatched indentations at 'else' with 'if'", "mismatched indentations at 'end' with 'else'")

      assert_warning("unless true\n  end", "mismatched indentations at 'end' with 'unless'")
      assert_warning("unless true\n  else\nend", "mismatched indentations at 'else' with 'unless'", "mismatched indentations at 'end' with 'else'")

      assert_warning("while true\n  end", "mismatched indentations at 'end' with 'while'")
      assert_warning("until true\n  end", "mismatched indentations at 'end' with 'until'")

      assert_warning("begin\n  end", "mismatched indentations at 'end' with 'begin'")
      assert_warning("begin\n  rescue\nend", "mismatched indentations at 'rescue' with 'begin'")
      assert_warning("begin\n  ensure\nend", "mismatched indentations at 'ensure' with 'begin'")
      assert_warning("begin\nrescue\n  else\nend", "mismatched indentations at 'else' with 'begin'", "mismatched indentations at 'end' with 'else'")
      assert_warning("begin\n  rescue\n    ensure\n      end", "mismatched indentations at 'rescue' with 'begin'", "mismatched indentations at 'ensure' with 'begin'", "mismatched indentations at 'end' with 'begin'");

      assert_warning("def foo\n  end", "mismatched indentations at 'end' with 'def'")
      assert_warning("def foo\n  rescue\nend", "mismatched indentations at 'rescue' with 'def'")
      assert_warning("def foo\n  ensure\nend", "mismatched indentations at 'ensure' with 'def'")
      assert_warning("def foo\nrescue\n  else\nend", "mismatched indentations at 'else' with 'def'", "mismatched indentations at 'end' with 'else'")
      assert_warning("def foo\n  rescue\n    ensure\n      end", "mismatched indentations at 'rescue' with 'def'", "mismatched indentations at 'ensure' with 'def'", "mismatched indentations at 'end' with 'def'");

      assert_warning("class Foo\n  end", "mismatched indentations at 'end' with 'class'")
      assert_warning("class Foo\n  rescue\nend", "mismatched indentations at 'rescue' with 'class'")
      assert_warning("class Foo\n  ensure\nend", "mismatched indentations at 'ensure' with 'class'")
      assert_warning("class Foo\nrescue\n  else\nend", "mismatched indentations at 'else' with 'class'", "mismatched indentations at 'end' with 'else'")
      assert_warning("class Foo\n  rescue\n    ensure\n      end", "mismatched indentations at 'rescue' with 'class'", "mismatched indentations at 'ensure' with 'class'", "mismatched indentations at 'end' with 'class'");

      assert_warning("module Foo\n  end", "mismatched indentations at 'end' with 'module'")
      assert_warning("module Foo\n  rescue\nend", "mismatched indentations at 'rescue' with 'module'")
      assert_warning("module Foo\n  ensure\nend", "mismatched indentations at 'ensure' with 'module'")
      assert_warning("module Foo\nrescue\n  else\nend", "mismatched indentations at 'else' with 'module'", "mismatched indentations at 'end' with 'else'")
      assert_warning("module Foo\n  rescue\n    ensure\n      end", "mismatched indentations at 'rescue' with 'module'", "mismatched indentations at 'ensure' with 'module'", "mismatched indentations at 'end' with 'module'");

      assert_warning("class << foo\n  end", "mismatched indentations at 'end' with 'class'")
      assert_warning("class << foo\n  rescue\nend", "mismatched indentations at 'rescue' with 'class'")
      assert_warning("class << foo\n  ensure\nend", "mismatched indentations at 'ensure' with 'class'")
      assert_warning("class << foo\nrescue\n  else\nend", "mismatched indentations at 'else' with 'class'", "mismatched indentations at 'end' with 'else'")
      assert_warning("class << foo\n  rescue\n    ensure\n      end", "mismatched indentations at 'rescue' with 'class'", "mismatched indentations at 'ensure' with 'class'", "mismatched indentations at 'end' with 'class'");

      assert_warning("case 1; when 2\n  end", "mismatched indentations at 'end' with 'case'")
      assert_warning("case 1; in 2\n  end", "mismatched indentations at 'end' with 'case'")

      assert_warning("  case 1\nwhen 2\n  end", "mismatched indentations at 'when' with 'case'")
      refute_warning("case 1\n  when 2\n    when 3\nend") # case/when allows more indentation

      assert_warning("-> {\n  }", "mismatched indentations at '}' with '->'")
      assert_warning("-> do\n  end", "mismatched indentations at 'end' with '->'")
      assert_warning("-> do\n  rescue\nend", "mismatched indentations at 'rescue' with '->'")
      assert_warning("-> do\n  ensure\nend", "mismatched indentations at 'ensure' with '->'")
      assert_warning("-> do\nrescue\n  else\nend", "mismatched indentations at 'else' with '->'", "mismatched indentations at 'end' with 'else'")
      assert_warning("-> do\n  rescue\n    ensure\n      end", "mismatched indentations at 'rescue' with '->'", "mismatched indentations at 'ensure' with '->'", "mismatched indentations at 'end' with '->'");
      assert_warning("foo do\nrescue\n  else\nend", "mismatched indentations at 'end' with 'else'")

      refute_warning("class Foo; end") # same line
      refute_warning("; class Foo\nend") # non whitespace on opening line
      refute_warning("\tclass Foo\n        end") # tab stop matches space
      refute_warning("    \tclass Foo\n        end") # tab stop matches space
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

    def test_numbered_reference
      assert_warning("_ = _ = $999999999999999999999", "too big for a number variable, always nil")
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

      refute_warning("def foo; bar = 1; end", line: -2, compare: false)
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

    if RbConfig::CONFIG["host_os"].match?(/bccwin|cygwin|djgpp|mingw|mswin|wince/i)
      def test_shebang_ending_with_carriage_return
        refute_warning("#!ruby\r\np(123)\n", compare: false)
      end
    else
      def test_shebang_ending_with_carriage_return
        msg = "shebang line ending with \\r may cause problems"

        assert_warning(<<~RUBY, msg, compare: false, main_script: true)
          #!ruby\r
          p(123)
        RUBY

        assert_warning(<<~RUBY, msg, compare: false, main_script: true)
          #!ruby \r
          p(123)
        RUBY

        assert_warning(<<~RUBY, msg, compare: false, main_script: true)
          #!ruby -Eutf-8\r
          p(123)
        RUBY

        # Used with the `-x` object, to ignore the script up until the first
        # shebang that mentioned "ruby".
        assert_warning(<<~SCRIPT, msg, compare: false, main_script: true)
          #!/usr/bin/env bash
          # Some initial shell script or other content
          # that Ruby should ignore
          echo "This is shell script part"
          exit 0

          #! /usr/bin/env ruby -Eutf-8\r
          # Ruby script starts here
          puts "Hello from Ruby!"
        SCRIPT

        refute_warning("#ruby not_a_shebang\r\n", compare: false, main_script: true)

        # CRuby doesn't emit the warning if a malformed file only has `\r` and
        # not `\n`. https://bugs.ruby-lang.org/issues/20700.
        refute_warning("#!ruby\r", compare: false, main_script: true)
      end
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

    def assert_warning(source, *messages, compare: true, **options)
      warnings = Prism.parse(source, **options).warnings
      assert_equal messages.length, warnings.length, "Expected #{messages.length} warning(s) in #{source.inspect}, got #{warnings.map(&:message).inspect}"

      warnings.zip(messages).each do |warning, message|
        assert_include warning.message, message
      end

      if compare && defined?(RubyVM::AbstractSyntaxTree)
        stderr = capture_stderr { RubyVM::AbstractSyntaxTree.parse(source) }
        messages.each { |message| assert_include stderr, message }
      end
    end

    def refute_warning(source, compare: true, **options)
      assert_empty Prism.parse(source, **options).warnings

      if compare && defined?(RubyVM::AbstractSyntaxTree)
        assert_empty capture_stderr { RubyVM::AbstractSyntaxTree.parse(source) }
      end
    end

    def capture_stderr
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
