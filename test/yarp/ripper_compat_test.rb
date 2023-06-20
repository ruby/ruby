# frozen_string_literal: true

require "yarp_test_helper"

module YARP
  class RipperCompatTest < Test::Unit::TestCase
    def test_1_plus_2
      assert_equivalent("1 + 2")
    end

    def test_2_minus_3
      assert_equivalent("2 - 3")
    end

    private

    def assert_equivalent(source)
      assert_equal Ripper.sexp_raw(source), RipperCompat.sexp_raw(source)
    end
  end
end
