# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class IntegerBaseFlagsTest < TestCase
    # Through some bit hackery, we want to allow consumers to use the integer
    # base flags as the base itself. It has a nice property that the current
    # alignment provides them in the correct order. So here we test that our
    # assumption holds so that it doesn't change out from under us.
    #
    # In C, this would look something like:
    #
    #     ((flags & ~DECIMAL) >> 1) || 10
    #
    # We have to do some other work in Ruby because 0 is truthy and ~ on an
    # integer doesn't have a fixed width.
    def test_flags
      assert_equal 2, base("0b1")
      assert_equal 8, base("0o1")
      assert_equal 10, base("0d1")
      assert_equal 16, base("0x1")
    end

    private

    def base(source)
      node = Prism.parse_statement(source)
      value = (node.send(:flags) & (0b111100 - IntegerBaseFlags::DECIMAL)) >> 1
      value == 0 ? 10 : value
    end
  end
end
