# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class RipperCompatTest < TestCase
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
      if RUBY_ENGINE != "truffleruby"
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

      # assert_equivalent("foo(bar 1)")
      # assert_equivalent("foo bar 1")
      # assert_equivalent("foo(bar 1) { 7 }")
    end

    def test_method_calls_on_immediate_values
      assert_equivalent("7.even?")
      assert_equivalent("!1")
      assert_equivalent("7 && 7")
      assert_equivalent("7 and 7")
      assert_equivalent("7 || 7")
      assert_equivalent("7 or 7")
      #assert_equivalent("'racecar'.reverse")
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

    def test_begin_rescue
      assert_equivalent("begin a; rescue; c; ensure b; end")
    end

    def test_break
      assert_equivalent("foo { break }")
      assert_equivalent("foo { break 7 }")
      assert_equivalent("foo { break [1, 2, 3] }")
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

    private

    def assert_equivalent(source)
      expected = Ripper.sexp_raw(source)

      refute_nil expected
      assert_equal expected, RipperCompat.sexp_raw(source)
    end
  end

  class RipperCompatFixturesTest < TestCase
    #base = File.join(__dir__, "fixtures")
    #relatives = ENV["FOCUS"] ? [ENV["FOCUS"]] : Dir["**/*.txt", base: base]
    relatives = [
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

        expected = Ripper.sexp_raw(source)
        if expected.nil?
          puts "Could not parse #{path.inspect}!"
        end
        refute_nil expected
        assert_equal expected, RipperCompat.sexp_raw(source)
      end
    end

  end
end
