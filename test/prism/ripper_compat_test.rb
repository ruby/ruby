# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class RipperCompatTest < TestCase
    def test_binary
      assert_equivalent("1 + 2")
      assert_equivalent("3 - 4 * 5")
      assert_equivalent("6 / 7; 8 % 9")
    end

    def test_unary
      assert_equivalent("-7")
    end

    def test_unary_parens
      assert_equivalent("-(7)")
      assert_equivalent("(-7)")
      assert_equivalent("(-\n7)")
    end

    def test_binary_parens
      assert_equivalent("(3 + 7) * 4")
    end

    def test_ident
      assert_equivalent("foo")
    end

    def test_range
      assert_equivalent("(...2)")
      assert_equivalent("(..2)")
      assert_equivalent("(1...2)")
      assert_equivalent("(1..2)")
      assert_equivalent("(foo..-7)")
    end

    def test_parentheses
      assert_equivalent("()")
      assert_equivalent("(1)")
      assert_equivalent("(1; 2)")
    end

    def test_numbers
      assert_equivalent("[1, -1, +1, 1.0, -1.0, +1.0]")
      assert_equivalent("[1r, -1r, +1r, 1.5r, -1.5r, +1.5r]")
      assert_equivalent("[1i, -1i, +1i, 1.5i, -1.5i, +1.5i]")
      assert_equivalent("[1ri, -1ri, +1ri, 1.5ri, -1.5ri, +1.5ri]")
    end

    private

    def assert_equivalent(source)
      expected = Ripper.sexp_raw(source)

      refute_nil expected
      assert_equal expected, RipperCompat.sexp_raw(source)
    end
  end
end
