# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class RipperCompatTest < TestCase
    def test_binary
      assert_equivalent("1 + 2")
      assert_equivalent("3 - 4 * 5")
      assert_equivalent("6 / 7; 8 % 9")
    end

    private

    def assert_equivalent(source)
      assert_equal Ripper.sexp_raw(source), RipperCompat.sexp_raw(source)
    end
  end
end
