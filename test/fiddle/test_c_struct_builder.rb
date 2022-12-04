# frozen_string_literal: true
begin
  require_relative 'helper'
  require 'fiddle/struct'
  require 'fiddle/cparser'
  require 'fiddle/import'
rescue LoadError
end

module Fiddle
  class TestCStructBuilder < TestCase
    include Fiddle::CParser
    extend Fiddle::Importer

    RBasic = struct ['void * flags',
                     'void * klass' ]


    RObject = struct [
      { 'basic' => RBasic },
      { 'as'    => union([
                          { 'heap'=> struct([ 'uint32_t numiv',
                                              'void * ivptr',
                                              'void * iv_index_tbl' ]) },
                             'void *ary[3]' ])}
    ]


    def test_basic_embedded_members
      assert_equal 0, RObject.offsetof("basic.flags")
      assert_equal Fiddle::SIZEOF_VOIDP, RObject.offsetof("basic.klass")
    end

    def test_embedded_union_members
      assert_equal 2 * Fiddle::SIZEOF_VOIDP, RObject.offsetof("as")
      assert_equal 2 * Fiddle::SIZEOF_VOIDP, RObject.offsetof("as.heap")
      assert_equal 2 * Fiddle::SIZEOF_VOIDP, RObject.offsetof("as.heap.numiv")
      assert_equal 3 * Fiddle::SIZEOF_VOIDP, RObject.offsetof("as.heap.ivptr")
      assert_equal 4 * Fiddle::SIZEOF_VOIDP, RObject.offsetof("as.heap.iv_index_tbl")
    end

    def test_as_ary
      assert_equal 2 * Fiddle::SIZEOF_VOIDP, RObject.offsetof("as.ary")
    end

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
