# frozen_string_literal: true

require_relative "test_helper"

return if Prism::BACKEND == :FFI

module Prism
  class MemsizeTest < TestCase
    def test_memsize
      result = Debug.memsize("2 + 3")

      assert_equal 5, result[:length]
      assert_kind_of Integer, result[:memsize]
      assert_equal 6, result[:node_count]
    end
  end
end
