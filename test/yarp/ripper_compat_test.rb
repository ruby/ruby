# frozen_string_literal: true

require "test_helper"

module YARP
  class RipperCompatTest < Test::Unit::TestCase
    test "1 + 2" do
      assert_equivalent("1 + 2")
    end

    test "2 - 3" do
      assert_equivalent("2 - 3")
    end

    private

    def assert_equivalent(source)
      assert_equal Ripper.sexp_raw(source), RipperCompat.sexp_raw(source)
    end
  end
end
