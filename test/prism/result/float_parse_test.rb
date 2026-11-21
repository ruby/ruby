# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
  class FloatParseTest < TestCase
    def test_float_parse
      assert_float_parse("3ff8000000000000", "1.5")
      assert_float_parse("4000000000000000", "+2.0")
      assert_float_parse("42a2309d03c48000", "1_000.000_1e1_0")
      assert_float_parse("3fd3333333333334", "0.30000000000000004")
      assert_float_parse("44b52d02c7e14af6", "1e23")
      assert_float_parse("0000000000000000", "0.0e99999999999999999999")
    end

    def test_float_parse_ties
      # 2**53 + 1 is halfway between two doubles, so it rounds to the even one,
      # and anything past it rounds up.
      assert_float_parse("4340000000000000", "9007199254740993.0")
      assert_float_parse("4340000000000001", "9007199254740993.0000000000000000000000001")

      # 1 + 2**-53 is halfway between 1 and the next double. A nonzero digit
      # far past the first 768 significant digits still breaks the tie.
      halfway = "1.00000000000000011102230246251565404236316680908203125"
      assert_float_parse("3ff0000000000000", halfway)
      assert_float_parse("3ff0000000000001", "#{halfway}#{"0" * 800}1")

      # Just below the halfway point between two doubles near 7e-77.
      assert_float_parse(
        "30205e1d07346324",
        "7.06768076391090364561370091321831414708692372912499013908562533927508" \
        "1336861732843770134770676005047023865780514951295302778156921388487571" \
        "7771532077839355963550153097003194004494490890037373953536103954320424" \
        "23635721206665039062499999999999E-77"
      )
    end

    def test_float_parse_limits
      assert_float_parse("7fefffffffffffff", "1.7976931348623157e308")
      assert_float_parse("7ff0000000000000", "1.7976931348623159e308")
      assert_float_parse("000fffffffffffff", "2.2250738585072011e-308")
      assert_float_parse("0000000000000001", "4.9e-324")
      assert_float_parse("0000000000000001", "2.4703282292062328e-324")
      assert_float_parse("0000000000000000", "2.4703282292062327e-324")

      # The halfway point between the largest subnormal and the smallest
      # normal, which rounds up to the even one.
      assert_float_parse("0010000000000000", "#{(2**53 - 1) * 5**1075}e-1075")
    end

    private

    def assert_float_parse(expected, source)
      node = Ruby::Prism.parse_statement(source)
      assert_kind_of FloatNode, node
      assert_equal expected, [node.value].pack("G").unpack1("H*"), source
    end
  end
end
