# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class RipperTestCase < TestCase
    private

    def truffleruby?
      RUBY_ENGINE == "truffleruby"
    end

    # Ripper produces certain ambiguous structures. For instance, it often
    # adds an :args_add_block with "false" as the block meaning there is
    # no block call. It can be hard to tell which of multiple equivalent
    # structures it will produce. This method attempts to return a normalized
    # comparable structure.
    def normalized_sexp(parsed)
      if parsed.is_a?(Array)
        # For args_add_block, if the third entry is nil or false, remove it.
        # Note that CRuby Ripper uses false for no block, while older JRuby
        # uses nil. We need to do this for both.
        return normalized_sexp(parsed[1]) if parsed[0] == :args_add_block && !parsed[2]

        parsed.each.with_index do |item, idx|
          if item.is_a?(Array)
            parsed[idx] = normalized_sexp(parsed[idx])
          end
        end
      end

      parsed
    end

    def assert_ripper_equivalent(source, path: "inline source code")
      expected = Ripper.sexp_raw(source)

      refute_nil expected, "Could not parse #{path} with Ripper!"
      expected = normalized_sexp(expected)
      actual = Prism::Translation::Ripper.sexp_raw(source)
      refute_nil actual, "Could not parse #{path} with Prism!"
      actual = normalized_sexp(actual)
      assert_equal expected, actual, "Expected Ripper and Prism to give equivalent output for #{path}!"
    end
  end

  class RipperShortSourceTest < RipperTestCase
    def test_binary
      assert_equivalent("1 + 2")
      assert_equivalent("3 - 4 * 5")
      assert_equivalent("6 / 7; 8 % 9")
    end

    def test_unary
      assert_equivalent("-7")
    end

    def test_unary_parens
      assert_equivalent("-(7)")
      assert_equivalent("(-7)")
      assert_equivalent("(-\n7)")
    end

    def test_binary_parens
      assert_equivalent("(3 + 7) * 4")
    end

    def test_method_calls_with_variable_names
      assert_equivalent("foo")
      assert_equivalent("foo()")
      assert_equivalent("foo -7")
      assert_equivalent("foo(-7)")
      assert_equivalent("foo(1, 2, 3)")
      assert_equivalent("foo 1")
      assert_equivalent("foo bar")
      assert_equivalent("foo 1, 2")
      assert_equivalent("foo.bar")

      # TruffleRuby prints emoji symbols differently in a way that breaks here.
      unless truffleruby?
        assert_equivalent("🗻")
        assert_equivalent("🗻.location")
        assert_equivalent("foo.🗻")
        assert_equivalent("🗻.😮!")
        assert_equivalent("🗻 🗻,🗻,🗻")
      end

      assert_equivalent("foo&.bar")
      assert_equivalent("foo { bar }")
      assert_equivalent("foo.bar { 7 }")
      assert_equivalent("foo(1) { bar }")
      assert_equivalent("foo(bar)")
      assert_equivalent("foo(bar(1))")
      assert_equivalent("foo(bar(1)) { 7 }")
      assert_equivalent("foo bar(1)")
    end

    def test_method_call_blocks
      assert_equivalent("foo { |a| a }")

      assert_equivalent("foo(bar 1)")
      assert_equivalent("foo bar 1")
      assert_equivalent("foo(bar 1) { 7 }")
      assert_equivalent("foo(bar 1) {; 7 }")
      assert_equivalent("foo(bar 1) {;}")

      assert_equivalent("foo do\n  bar\nend")
      assert_equivalent("foo do\nend")
      assert_equivalent("foo do; end")
      assert_equivalent("foo do bar; end")
      assert_equivalent("foo do bar end")
      assert_equivalent("foo do; bar; end")
    end

    def test_method_calls_on_immediate_values
      assert_equivalent("7.even?")
      assert_equivalent("!1")
      assert_equivalent("7 && 7")
      assert_equivalent("7 and 7")
      assert_equivalent("7 || 7")
      assert_equivalent("7 or 7")
      assert_equivalent("'racecar'.reverse")
    end

    def test_range
      assert_equivalent("(...2)")
      assert_equivalent("(..2)")
      assert_equivalent("(1...2)")
      assert_equivalent("(1..2)")
      assert_equivalent("(foo..-7)")
    end

    def test_parentheses
      assert_equivalent("()")
      assert_equivalent("(1)")
      assert_equivalent("(1; 2)")
    end

    def test_numbers
      assert_equivalent("[1, -1, +1, 1.0, -1.0, +1.0]")
      assert_equivalent("[1r, -1r, +1r, 1.5r, -1.5r, +1.5r]")
      assert_equivalent("[1i, -1i, +1i, 1.5i, -1.5i, +1.5i]")
      assert_equivalent("[1ri, -1ri, +1ri, 1.5ri, -1.5ri, +1.5ri]")
    end

    def test_begin_end
      # Empty begin
      assert_equivalent("begin; end")
      assert_equivalent("begin end")
      assert_equivalent("begin; rescue; end")

      assert_equivalent("begin:s.l end")
    end

    def test_begin_rescue
      # Rescue with exception(s)
      assert_equivalent("begin a; rescue Exception => ex; c; end")
      assert_equivalent("begin a; rescue RuntimeError => ex; c; rescue Exception => ex; d; end")
      assert_equivalent("begin a; rescue RuntimeError => ex; c; rescue Exception => ex; end")
      assert_equivalent("begin a; rescue RuntimeError,FakeError,Exception => ex; c; end")
      assert_equivalent("begin a; rescue RuntimeError,FakeError,Exception; c; end")

      # Empty rescue
      assert_equivalent("begin a; rescue; ensure b; end")
      assert_equivalent("begin a; rescue; end")

      assert_equivalent("begin; a; ensure; b; end")
    end

    def test_begin_ensure
      # Empty ensure
      assert_equivalent("begin a; rescue; c; ensure; end")
      assert_equivalent("begin a; ensure; end")
      assert_equivalent("begin; ensure; end")

      # Ripper treats statements differently, depending whether there's
      # a semicolon after the keyword.
      assert_equivalent("begin a; rescue; c; ensure b; end")
      assert_equivalent("begin a; rescue c; ensure b; end")
      assert_equivalent("begin a; rescue; c; ensure; b; end")

      # Need to make sure we're handling multibyte characters correctly for source offsets
      assert_equivalent("begin 🗻; rescue; c;     ensure;🗻🗻🗻🗻🗻; end")
      assert_equivalent("begin 🗻; rescue; c;     ensure 🗻🗻🗻🗻🗻; end")
    end

    def test_break
      assert_equivalent("foo { break }")
      assert_equivalent("foo { break 7 }")
      assert_equivalent("foo { break [1, 2, 3] }")
    end

    def test_constants
      assert_equivalent("Foo")
      assert_equivalent("Foo + F🗻")
      assert_equivalent("Foo = 'soda'")
    end

    def test_op_assign
      assert_equivalent("a += b")
      assert_equivalent("a -= b")
      assert_equivalent("a *= b")
      assert_equivalent("a /= b")
    end

    def test_arrays
      assert_equivalent("[1, 2, 7]")
      assert_equivalent("[1, [2, 7]]")
    end

    def test_array_refs
      assert_equivalent("a[1]")
      assert_equivalent("a[1] = 7")
    end

    def test_strings
      assert_equivalent("'a'")
      assert_equivalent("'a\01'")
      assert_equivalent("`a`")
      assert_equivalent("`a\07`")
      assert_equivalent('"a#{1}c"')
      assert_equivalent('"a#{1}b#{2}c"')
      assert_equivalent("`f\oo`")
    end

    def test_symbols
      assert_equivalent(":a")
      assert_equivalent(":'a'")
      assert_equivalent(':"a"')
      assert_equivalent("%s(foo)")
    end

    def test_assign
      assert_equivalent("a = b")
      assert_equivalent("a = 1")
    end

    def test_alias
      assert_equivalent("alias :foo :bar")
      assert_equivalent("alias $a $b")
      assert_equivalent("alias $a $'")
      assert_equivalent("alias foo bar")
      assert_equivalent("alias foo if")
      assert_equivalent("alias :'def' :\"abc\#{1}\"")
      assert_equivalent("alias :\"abc\#{1}\" :'def'")

      unless truffleruby?
        assert_equivalent("alias :foo :Ę") # Uppercase Unicode character is a constant
        assert_equivalent("alias :Ę :foo")
      end

      assert_equivalent("alias foo +")
      assert_equivalent("alias foo :+")
      assert_equivalent("alias :foo :''")
      assert_equivalent("alias :'' :foo")
    end

    Translation::Ripper
    RUBY_KEYWORDS = Translation.const_get(:RipperCompiler)::RUBY_KEYWORDS

    # This is *exactly* the kind of thing where Ripper would have a weird
    # special case we didn't handle correctly. We're still testing with
    # a leading colon since putting random keywords there will often get
    # parse errors. Mostly we want to know that Ripper will use :@kw
    # instead of :@ident for the lexer symbol for all of these.
    def test_keyword_aliases
      RUBY_KEYWORDS.each do |keyword|
        assert_equivalent("alias :foo :#{keyword}")
      end
    end

    private

    def assert_equivalent(source)
      assert_ripper_equivalent(source)
    end
  end

  class RipperFixturesTest < RipperTestCase
    #base = File.join(__dir__, "fixtures")
    #relatives = ENV["FOCUS"] ? [ENV["FOCUS"]] : Dir["**/*.txt", base: base]
    relatives = [
      "alias.txt",
      "arithmetic.txt",
      "booleans.txt",
      "boolean_operators.txt",
      # "break.txt", # No longer parseable by Ripper in CRuby 3.3.0+
      "comments.txt",
      "integer_operations.txt",
    ]

    relatives.each do |relative|
      define_method "test_ripper_filepath_#{relative}" do
        path = File.join(__dir__, "fixtures", relative)

        # First, read the source from the path. Use binmode to avoid converting CRLF on Windows,
        # and explicitly set the external encoding to UTF-8 to override the binmode default.
        source = File.read(path, binmode: true, external_encoding: Encoding::UTF_8)

        assert_ripper_equivalent(source, path: path)
      end
    end
  end
end
