# frozen_string_literal: true

require_relative "../test_helper"

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

      num = 99 ** 99
      assert_integer_parse(num, "0b#{num.to_s(2)}")
      assert_integer_parse(num, "0o#{num.to_s(8)}")
      assert_integer_parse(num, "0d#{num.to_s(10)}")
      assert_integer_parse(num, "0x#{num.to_s(16)}")
    end

    private

    def assert_integer_parse(expected, source = expected.to_s)
      assert_equal expected, Prism.parse_statement(source).value
    end
  end
end
