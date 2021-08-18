# frozen_string_literal: true
begin
  require_relative 'helper'
  require 'fiddle/struct'
  require 'fiddle/cparser'
rescue LoadError
end

module Fiddle
  class TestCStructBuilder < TestCase
    include Fiddle::CParser

    def test_offsetof
      types, members = parse_struct_signature(['int64_t i','char c'])
      my_struct = Fiddle::CStructBuilder.create(Fiddle::CStruct, types, members)
      assert_equal 0, my_struct.offsetof("i")
      assert_equal Fiddle::SIZEOF_INT64_T, my_struct.offsetof("c")
    end

    def test_offset_with_gap
      types, members = parse_struct_signature(['void *p', 'char c', 'long x'])
      my_struct = Fiddle::CStructBuilder.create(Fiddle::CStruct, types, members)

      assert_equal PackInfo.align(0, ALIGN_VOIDP), my_struct.offsetof("p")
      assert_equal PackInfo.align(SIZEOF_VOIDP, ALIGN_CHAR), my_struct.offsetof("c")
      assert_equal SIZEOF_VOIDP + PackInfo.align(SIZEOF_CHAR, ALIGN_LONG), my_struct.offsetof("x")
    end

    def test_union_offsetof
      types, members = parse_struct_signature(['int64_t i','char c'])
      my_struct = Fiddle::CStructBuilder.create(Fiddle::CUnion, types, members)
      assert_equal 0, my_struct.offsetof("i")
      assert_equal 0, my_struct.offsetof("c")
    end
  end
end if defined?(Fiddle)
