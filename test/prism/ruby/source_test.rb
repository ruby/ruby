# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class SourceTest < TestCase
    def test_line_to_byte_offset
      parse_result = Prism.parse(<<~SRC)
      abcd
      efgh
      ijkl
      SRC
      source = parse_result.source

      assert_equal 0, source.line_to_byte_offset(1)
      assert_equal 5, source.line_to_byte_offset(2)
      assert_equal 10, source.line_to_byte_offset(3)
      assert_equal 15, source.line_to_byte_offset(4)
      e = assert_raise(ArgumentError) { source.line_to_byte_offset(5) }
      assert_equal "line 5 is out of range", e.message
      e = assert_raise(ArgumentError) { source.line_to_byte_offset(0) }
      assert_equal "line 0 is out of range", e.message
      e = assert_raise(ArgumentError) { source.line_to_byte_offset(-1) }
      assert_equal "line -1 is out of range", e.message
    end

    def test_line_to_byte_offset_with_start_line
      parse_result = Prism.parse(<<~SRC, line: 11)
      abcd
      efgh
      ijkl
      SRC
      source = parse_result.source

      assert_equal 0, source.line_to_byte_offset(11)
      assert_equal 5, source.line_to_byte_offset(12)
      assert_equal 10, source.line_to_byte_offset(13)
      assert_equal 15, source.line_to_byte_offset(14)
      e = assert_raise(ArgumentError) { source.line_to_byte_offset(15) }
      assert_equal "line 15 is out of range", e.message
      e = assert_raise(ArgumentError) { source.line_to_byte_offset(10) }
      assert_equal "line 10 is out of range", e.message
      e = assert_raise(ArgumentError) { source.line_to_byte_offset(9) }
      assert_equal "line 9 is out of range", e.message
    end
  end
end
