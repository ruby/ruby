# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class StaticInspectTest < TestCase
    def test_false
      assert_equal "false", static_inspect("false")
    end

    def test_float
      assert_equal "0.25", static_inspect("0.25")
      assert_equal "5.125", static_inspect("5.125")

      assert_equal "0.0", static_inspect("0.0")
      assert_equal "-0.0", static_inspect("-0.0")

      assert_equal "1.0e+100", static_inspect("1e100")
      assert_equal "-1.0e+100", static_inspect("-1e100")

      assert_equal "Infinity", static_inspect("1e1000")
      assert_equal "-Infinity", static_inspect("-1e1000")
    end

    def test_imaginary
      assert_equal "(0+1i)", static_inspect("1i")
      assert_equal "(0-1i)", static_inspect("-1i")
    end

    def test_integer
      assert_equal "1000", static_inspect("1_0_0_0")
      assert_equal "10000000000000000000000000000", static_inspect("1_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0")
    end

    def test_nil
      assert_equal "nil", static_inspect("nil")
    end

    def test_rational
      assert_equal "(0/1)", static_inspect("0r")
      assert_equal "(1/1)", static_inspect("1r")
      assert_equal "(1/1)", static_inspect("1.0r")
      assert_equal "(77777/1000)", static_inspect("77.777r")
    end

    def test_regular_expression
      assert_equal "/.*/", static_inspect("/.*/")
      assert_equal "/.*/i", static_inspect("/.*/i")
      assert_equal "/.*/", static_inspect("/.*/u")
      assert_equal "/.*/n", static_inspect("/.*/un")
    end

    def test_source_encoding
      assert_equal "#<Encoding:UTF-8>", static_inspect("__ENCODING__")
      assert_equal "#<Encoding:Windows-31J>", static_inspect("__ENCODING__", encoding: "Windows-31J")
    end

    def test_source_file
      assert_equal __FILE__.inspect, static_inspect("__FILE__", filepath: __FILE__, frozen_string_literal: true)
    end

    def test_source_line
      assert_equal "1", static_inspect("__LINE__")
      assert_equal "5", static_inspect("__LINE__", line: 5)
    end

    def test_string
      assert_equal "\"\"", static_inspect('""', frozen_string_literal: true)
      assert_equal "\"Hello, World!\"", static_inspect('"Hello, World!"', frozen_string_literal: true)
      assert_equal "\"\\a\"", static_inspect("\"\\a\"", frozen_string_literal: true)
    end

    def test_symbol
      assert_equal ":foo", static_inspect(":foo")
      assert_equal ":foo", static_inspect("%s[foo]")
    end

    def test_true
      assert_equal "true", static_inspect("true")
    end

    private

    def static_inspect(source, **options)
      warnings = Prism.parse("{ #{source} => 1, #{source} => 1 }", **options).warnings
      warnings.last.message[/^key (.+) is duplicated and overwritten on line \d/, 1]
    end
  end
end
