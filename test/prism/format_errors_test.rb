# frozen_string_literal: true

require_relative "test_helper"

return if Prism::BACKEND == :FFI

module Prism
  class FormatErrorsTest < TestCase
    def test_format_errors
      assert_equal <<~ERROR, Debug.format_errors("<>", false)
        > 1 | <>
            | ^ cannot parse the expression
            |  ^ cannot parse the expression
      ERROR
    end
  end
end
