# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class SourceTest < TestCase
    def test_byte_offset
      source = Prism.parse(<<~SRC).source
      abcd
      efgh
      ijkl
      SRC

      assert_equal 0, source.byte_offset(1, 0)
      assert_equal 5, source.byte_offset(2, 0)
      assert_equal 10, source.byte_offset(3, 0)
      assert_equal 15, source.byte_offset(4, 0)

      error = assert_raise(ArgumentError) { source.byte_offset(5, 0) }
      assert_equal "line 5 is out of range", error.message

      error = assert_raise(ArgumentError) { source.byte_offset(0, 0) }
      assert_equal "line 0 is out of range", error.message

      error = assert_raise(ArgumentError) { source.byte_offset(-1, 0) }
      assert_equal "line -1 is out of range", error.message
    end

    def test_byte_offset_with_start_line
      source = Prism.parse(<<~SRC, line: 11).source
      abcd
      efgh
      ijkl
      SRC

      assert_equal 0, source.byte_offset(11, 0)
      assert_equal 5, source.byte_offset(12, 0)
      assert_equal 10, source.byte_offset(13, 0)
      assert_equal 15, source.byte_offset(14, 0)

      error = assert_raise(ArgumentError) { source.byte_offset(15, 0) }
      assert_equal "line 15 is out of range", error.message

      error = assert_raise(ArgumentError) { source.byte_offset(10, 0) }
      assert_equal "line 10 is out of range", error.message

      error = assert_raise(ArgumentError) { source.byte_offset(9, 0) }
      assert_equal "line 9 is out of range", error.message
    end
  end
end
