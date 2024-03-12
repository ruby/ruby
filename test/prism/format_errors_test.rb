# frozen_string_literal: true

require_relative "test_helper"

return if Prism::BACKEND == :FFI

module Prism
  class FormatErrorsTest < TestCase
    def test_format_errors
      assert_equal <<~ERROR, Debug.format_errors("<>", false)
        > 1 | <>
            | ^ unexpected '<', ignoring it
            |  ^ unexpected '>', ignoring it
      ERROR

      assert_equal <<~'ERROR', Debug.format_errors('"%W"\u"', false)
        > 1 | "%W"\u"
            |     ^ unexpected backslash, ignoring it
            |      ^ unexpected local variable or method, expecting end-of-input
            |        ^ unterminated string meets end of file
      ERROR
    end
  end
end
