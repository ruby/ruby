# frozen_string_literal: true

require_relative "test_helper"

return if Prism::BACKEND == :FFI

module Prism
  class NumberParseTest < TestCase
    def test_number_parse
      assert_number_parse(1)
      assert_number_parse(50)
      assert_number_parse(100)
      assert_number_parse(100, "1_0_0")

      assert_number_parse(10, "0b1010")
      assert_number_parse(10, "0B1010")
      assert_number_parse(10, "0o12")
      assert_number_parse(10, "0O12")
      assert_number_parse(10, "012")
      assert_number_parse(10, "0d10")
      assert_number_parse(10, "0D10")
      assert_number_parse(10, "0xA")
      assert_number_parse(10, "0XA")

      assert_number_parse(2**32)
      assert_number_parse(2**64 + 2**32)
      assert_number_parse(2**128 + 2**64 + 2**32)
    end

    private

    def assert_number_parse(expected, source = expected.to_s)
      assert_equal expected, Debug.number_parse(source)
    end
  end
end
