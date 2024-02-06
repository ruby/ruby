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
            |     ^ expected a newline or semicolon after the statement
            |     ^ invalid character `\`
            |        ^ expected a closing delimiter for the string literal
      ERROR
    end
  end
end
