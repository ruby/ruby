# frozen_string_literal: true
begin
  require_relative 'helper'
rescue LoadError
  return
end

begin
  require '-test-/memory_view'
rescue LoadError
  return
end

module Fiddle
  class TestMemoryView < TestCase
    def setup
      omit "MemoryView is unavailable" unless defined? Fiddle::MemoryView
    end

    def test_null_ptr
      assert_raise(ArgumentError) do
        MemoryView.new(Fiddle::NULL)
      end
    end

    def test_memory_view_from_unsupported_obj
      obj = Object.new
      assert_raise(ArgumentError) do
        MemoryView.new(obj)
      end
    end

    def test_memory_view_from_pointer
      str = Marshal.load(Marshal.dump("hello world"))
      ptr = Pointer[str]
      mview = MemoryView.new(ptr)
      begin
        assert_same(ptr, mview.obj)
        assert_equal(str.bytesize, mview.byte_size)
        assert_equal(true, mview.readonly?)
        assert_equal(nil, mview.format)
        assert_equal(1, mview.item_size)
        assert_equal(1, mview.ndim)
        assert_equal(nil, mview.shape)
        assert_equal(nil, mview.strides)
        assert_equal(nil, mview.sub_offsets)

        codes = str.codepoints
        assert_equal(codes, (0...str.bytesize).map {|i| mview[i] })
      ensure
        mview.release
      end
    end

    def test_memory_view_multi_dimensional
      omit "MemoryViewTestUtils is unavailable" unless defined? MemoryViewTestUtils

      buf = [ 1, 2, 3, 4,
              5, 6, 7, 8,
              9, 10, 11, 12 ].pack("l!*")
      shape = [3, 4]
      md = MemoryViewTestUtils::MultiDimensionalView.new(buf, "l!", shape, nil)
      mview = Fiddle::MemoryView.new(md)
      begin
        assert_equal(buf.bytesize, mview.byte_size)
        assert_equal("l!", mview.format)
        assert_equal(Fiddle::SIZEOF_LONG, mview.item_size)
        assert_equal(2, mview.ndim)
        assert_equal(shape, mview.shape)
        assert_equal([Fiddle::SIZEOF_LONG*4, Fiddle::SIZEOF_LONG], mview.strides)
        assert_equal(nil, mview.sub_offsets)
        assert_equal(1, mview[0, 0])
        assert_equal(4, mview[0, 3])
        assert_equal(6, mview[1, 1])
        assert_equal(10, mview[2, 1])
      ensure
        mview.release
      end
    end

    def test_memory_view_multi_dimensional_with_strides
      omit "MemoryViewTestUtils is unavailable" unless defined? MemoryViewTestUtils

      buf = [ 1, 2,  3,  4,  5,  6,  7,  8,
              9, 10, 11, 12, 13, 14, 15, 16 ].pack("l!*")
      shape = [2, 8]
      strides = [4*Fiddle::SIZEOF_LONG*2, Fiddle::SIZEOF_LONG*2]
      md = MemoryViewTestUtils::MultiDimensionalView.new(buf, "l!", shape, strides)
      mview = Fiddle::MemoryView.new(md)
      begin
        assert_equal("l!", mview.format)
        assert_equal(Fiddle::SIZEOF_LONG, mview.item_size)
        assert_equal(buf.bytesize, mview.byte_size)
        assert_equal(2, mview.ndim)
        assert_equal(shape, mview.shape)
        assert_equal(strides, mview.strides)
        assert_equal(nil, mview.sub_offsets)
        assert_equal(1, mview[0, 0])
        assert_equal(5, mview[0, 2])
        assert_equal(9, mview[1, 0])
        assert_equal(15, mview[1, 3])
      ensure
        mview.release
      end
    end

    def test_memory_view_multi_dimensional_with_multiple_members
      omit "MemoryViewTestUtils is unavailable" unless defined? MemoryViewTestUtils

      buf = [ 1, 2,  3,  4,  5,  6,  7,  8,
             -1, -2, -3, -4, -5, -6, -7, -8].pack("s*")
      shape = [2, 4]
      strides = [4*Fiddle::SIZEOF_SHORT*2, Fiddle::SIZEOF_SHORT*2]
      md = MemoryViewTestUtils::MultiDimensionalView.new(buf, "ss", shape, strides)
      mview = Fiddle::MemoryView.new(md)
      begin
        assert_equal("ss", mview.format)
        assert_equal(Fiddle::SIZEOF_SHORT*2, mview.item_size)
        assert_equal(buf.bytesize, mview.byte_size)
        assert_equal(2, mview.ndim)
        assert_equal(shape, mview.shape)
        assert_equal(strides, mview.strides)
        assert_equal(nil, mview.sub_offsets)
        assert_equal([1, 2], mview[0, 0])
        assert_equal([5, 6], mview[0, 2])
        assert_equal([-1, -2], mview[1, 0])
        assert_equal([-7, -8], mview[1, 3])
      ensure
        mview.release
      end
    end

    def test_export
      str = "hello world"
      mview_str = MemoryView.export(Pointer[str]) do |mview|
        mview.to_s
      end
      assert_equal(str, mview_str)
    end

    def test_release
      ptr = Pointer["hello world"]
      mview = MemoryView.new(ptr)
      assert_same(ptr, mview.obj)
      mview.release
      assert_nil(mview.obj)
    end

    def test_to_s
      # U+3042 HIRAGANA LETTER A
      data = "\u{3042}"
      ptr = Pointer[data]
      mview = MemoryView.new(ptr)
      begin
        string = mview.to_s
        assert_equal([data.b, true],
                     [string, string.frozen?])
      ensure
        mview.release
      end
    end

    def test_ractor_shareable
      omit("Need Ractor") unless defined?(Ractor)
      ptr = Pointer["hello world"]
      mview = MemoryView.new(ptr)
      begin
        assert_ractor_shareable(mview)
        assert_predicate(ptr, :frozen?)
      ensure
        mview.release
      end
    end
  end
end
