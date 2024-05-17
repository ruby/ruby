# frozen_string_literal: true

require_relative "test_helper"

return if Prism::BACKEND == :FFI

module Prism
  class FormatErrorsTest < TestCase
    def test_basic
      expected = <<~ERROR
        > 1 | <>
            | ^ unexpected '<', ignoring it
            |  ^ unexpected '>', ignoring it
      ERROR

      assert_equal expected, Debug.format_errors("<>", false)
    end

    def test_multiple
      expected = <<~ERROR
        > 1 | "%W"\\u"
            |     ^ unexpected backslash, ignoring it
            |      ^ unexpected local variable or method, expecting end-of-input
            |        ^ unterminated string meets end of file
      ERROR

      assert_equal expected, Debug.format_errors('"%W"\u"', false)
    end

    def test_truncate_start
      expected = <<~ERROR
        > 1 | ... <>
            |     ^ unexpected '<', ignoring it
            |      ^ unexpected '>', ignoring it
      ERROR

      assert_equal expected, Debug.format_errors("#{" " * 30}<>", false)
    end

    def test_truncate_end
      expected = <<~ERROR
        > 1 | <#{" " * 30} ...
            | ^ unexpected '<', ignoring it
      ERROR

      assert_equal expected, Debug.format_errors("<#{" " * 30}a", false)
    end

    def test_truncate_both
      expected = <<~ERROR
        > 1 | ... <#{" " * 30} ...
            |     ^ unexpected '<', ignoring it
      ERROR

      assert_equal expected, Debug.format_errors("#{" " * 30}<#{" " * 30}a", false)
    end
  end
end
