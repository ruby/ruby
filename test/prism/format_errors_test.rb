# frozen_string_literal: true

return if Prism::BACKEND == :FFI

require_relative "test_helper"

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
