# frozen_string_literal: true

require_relative "test_helper"

return if Prism::BACKEND == :FFI

module Prism
  class IntegerParseTest < TestCase
    def test_integer_parse
      assert_integer_parse(1)
      assert_integer_parse(50)
      assert_integer_parse(100)
      assert_integer_parse(100, "1_0_0")
      assert_integer_parse(8, "0_1_0")

      assert_integer_parse(10, "0b1010")
      assert_integer_parse(10, "0B1010")
      assert_integer_parse(10, "0o12")
      assert_integer_parse(10, "0O12")
      assert_integer_parse(10, "012")
      assert_integer_parse(10, "0d10")
      assert_integer_parse(10, "0D10")
      assert_integer_parse(10, "0xA")
      assert_integer_parse(10, "0XA")

      assert_integer_parse(2**32)
      assert_integer_parse(2**64 + 2**32)
      assert_integer_parse(2**128 + 2**64 + 2**32)
    end

    private

    def assert_integer_parse(expected, source = expected.to_s)
      integer, string = Debug.integer_parse(source)
      assert_equal expected, integer
      assert_equal expected.to_s, string
    end
  end
end
