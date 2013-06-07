# coding: ASCII-8BIT

require 'test/unit'
require "-test-/bignum"

class TestBignum < Test::Unit::TestCase
  class TestPack < Test::Unit::TestCase

    MSWORD_FIRST = Integer::INTEGER_PACK_MSWORD_FIRST
    LSWORD_FIRST = Integer::INTEGER_PACK_LSWORD_FIRST
    MSBYTE_FIRST = Integer::INTEGER_PACK_MSBYTE_FIRST
    LSBYTE_FIRST = Integer::INTEGER_PACK_LSBYTE_FIRST
    NATIVE_BYTE_ORDER = Integer::INTEGER_PACK_NATIVE_BYTE_ORDER
    LITTLE_ENDIAN = Integer::INTEGER_PACK_LITTLE_ENDIAN
    BIG_ENDIAN = Integer::INTEGER_PACK_BIG_ENDIAN

    def test_pack_zero
      assert_equal([0, "", 0], 0.test_pack(nil, 1, 0, BIG_ENDIAN))
    end

    def test_pack_argument_check
      assert_raise(ArgumentError) { 0.test_pack(nil, 1, 0, MSBYTE_FIRST) }
      assert_raise(ArgumentError) { 0.test_pack(nil, 1, 0, MSWORD_FIRST) }
      assert_raise(ArgumentError) { 0.test_pack(nil, 0, 0, BIG_ENDIAN) }
      assert_raise(ArgumentError) { 0.test_pack(nil, 1, 8, BIG_ENDIAN) }

      # assume sizeof(ssize_t) == sizeof(intptr_t)
      assert_raise(ArgumentError) { 0.test_pack(nil, 1 << ([""].pack("p").length * 8 - 1), 0, BIG_ENDIAN) }
    end

    def test_pack_wordsize
      assert_equal([1, "\x01", 1], 1.test_pack(nil, 1, 0, BIG_ENDIAN))
      assert_equal([1, "\x00\x01", 1], 1.test_pack(nil, 2, 0, BIG_ENDIAN))
      assert_equal([1, "\x00\x00\x01", 1], 1.test_pack(nil, 3, 0, BIG_ENDIAN))
      assert_equal([1, "\x01", 1], 1.test_pack(nil, 1, 0, LITTLE_ENDIAN))
      assert_equal([1, "\x01\x00", 1], 1.test_pack(nil, 2, 0, LITTLE_ENDIAN))
      assert_equal([1, "\x01\x00\x00", 1], 1.test_pack(nil, 3, 0, LITTLE_ENDIAN))
    end

    def test_pack_fixed_buffer
      assert_equal([0, "\x00\x00", 2], 0.test_pack("xx", 1, 0, BIG_ENDIAN))
      assert_equal([1, "\x00\x01", 2], 0x01.test_pack("xx", 1, 0, BIG_ENDIAN))
      assert_equal([1, "\x02\x01", 2], 0x0201.test_pack("xx", 1, 0, BIG_ENDIAN))
      assert_equal([2, "\x02\x01", 2], 0x030201.test_pack("xx", 1, 0, BIG_ENDIAN))
      assert_equal([2, "\x02\x01", 2], 0x04030201.test_pack("xx", 1, 0, BIG_ENDIAN))
      assert_equal([0, "\x00\x00", 2], 0.test_pack("xx", 1, 0, LITTLE_ENDIAN))
      assert_equal([1, "\x01\x00", 2], 0x01.test_pack("xx", 1, 0, LITTLE_ENDIAN))
      assert_equal([1, "\x01\x02", 2], 0x0201.test_pack("xx", 1, 0, LITTLE_ENDIAN))
      assert_equal([2, "\x01\x02", 2], 0x030201.test_pack("xx", 1, 0, LITTLE_ENDIAN))
      assert_equal([2, "\x01\x02", 2], 0x04030201.test_pack("xx", 1, 0, LITTLE_ENDIAN))
    end

    def test_pack_wordorder_and_endian
      assert_equal([1, "\x12\x34\x56\x78", 2], 0x12345678.test_pack(nil, 2, 0, MSWORD_FIRST|MSBYTE_FIRST))
      assert_equal([1, "\x34\x12\x78\x56", 2], 0x12345678.test_pack(nil, 2, 0, MSWORD_FIRST|LSBYTE_FIRST))
      assert_equal([1, "\x56\x78\x12\x34", 2], 0x12345678.test_pack(nil, 2, 0, LSWORD_FIRST|MSBYTE_FIRST))
      assert_equal([1, "\x78\x56\x34\x12", 2], 0x12345678.test_pack(nil, 2, 0, LSWORD_FIRST|LSBYTE_FIRST))
    end

    def test_pack_native_endian
      assert_equal([1, [0x1234].pack("S!"), 1], 0x1234.test_pack(nil, 2, 0, MSWORD_FIRST|NATIVE_BYTE_ORDER))
    end

    def test_pack_nail
      assert_equal([1, "\x01\x00\x00\x00\x01\x01", 6], 0b100011.test_pack(nil, 1, 7, BIG_ENDIAN))
      assert_equal([1, "\x01\x02\x03\x04\x05\x06\x07\x08", 8], 0x12345678.test_pack(nil, 1, 4, BIG_ENDIAN))
      assert_equal([1, "\x00\x12\x00\x34\x00\x56\x00\x78", 4], 0x12345678.test_pack(nil, 2, 8, BIG_ENDIAN))
    end

    def test_pack_sign
      assert_equal([-1, "\x01", 1], (-1).test_pack(nil, 1, 0, BIG_ENDIAN))
      assert_equal([-1, "\x80\x70\x60\x50\x40\x30\x20\x10", 8], (-0x8070605040302010).test_pack(nil, 1, 0, BIG_ENDIAN))
    end

    def test_unpack_zero
      assert_equal(0, Integer.test_unpack(0, "", 0, 1, 0, BIG_ENDIAN))
    end

    def test_unpack_argument_check
      assert_raise(ArgumentError) { Integer.test_unpack(1, "x", 1, 1, 0, MSBYTE_FIRST) }
      assert_raise(ArgumentError) { Integer.test_unpack(1, "x", 1, 1, 0, MSWORD_FIRST) }
      assert_raise(ArgumentError) { Integer.test_unpack(1, "x", 1, 0, 0, BIG_ENDIAN) }
      assert_raise(ArgumentError) { Integer.test_unpack(1, "x", 1, 1, 8, BIG_ENDIAN) }

      # assume sizeof(ssize_t) == sizeof(intptr_t)
      assert_raise(ArgumentError) { Integer.test_unpack(1, "x", 1, 1 << ([""].pack("p").length * 8 - 1), 0, BIG_ENDIAN) }
    end

    def test_unpack_wordsize
      assert_equal(1, Integer.test_unpack(1, "\x01", 1, 1, 0, BIG_ENDIAN))
      assert_equal(1, Integer.test_unpack(1, "\x00\x01", 1, 2, 0, BIG_ENDIAN))
      assert_equal(1, Integer.test_unpack(1, "\x00\x00\x01", 1, 3, 0, BIG_ENDIAN))
      assert_equal(1, Integer.test_unpack(1, "\x01", 1, 1, 0, LITTLE_ENDIAN))
      assert_equal(1, Integer.test_unpack(1, "\x01\x00", 1, 2, 0, LITTLE_ENDIAN))
      assert_equal(1, Integer.test_unpack(1, "\x01\x00\x00", 1, 3, 0, LITTLE_ENDIAN))
    end

    def test_unpack_wordorder_and_endian
      assert_equal(0x01020304, Integer.test_unpack(1, "\x01\x02\x03\x04", 2, 2, 0, MSWORD_FIRST|MSBYTE_FIRST))
      assert_equal(0x02010403, Integer.test_unpack(1, "\x01\x02\x03\x04", 2, 2, 0, MSWORD_FIRST|LSBYTE_FIRST))
      assert_equal(0x03040102, Integer.test_unpack(1, "\x01\x02\x03\x04", 2, 2, 0, LSWORD_FIRST|MSBYTE_FIRST))
      assert_equal(0x04030201, Integer.test_unpack(1, "\x01\x02\x03\x04", 2, 2, 0, LSWORD_FIRST|LSBYTE_FIRST))
    end

    def test_unpack_native_endian
      assert_equal("\x12\x34".unpack("S!")[0], Integer.test_unpack(1, "\x12\x34", 1, 2, 0, MSWORD_FIRST|NATIVE_BYTE_ORDER))
    end

    def test_unpack_nail
      assert_equal(0b100011, Integer.test_unpack(1, "\x01\x00\x00\x00\x01\x01", 6, 1, 7, BIG_ENDIAN))
      assert_equal(0x12345678, Integer.test_unpack(1, "\x01\x02\x03\x04\x05\x06\x07\x08", 8, 1, 4, BIG_ENDIAN))
      assert_equal(0x12345678, Integer.test_unpack(1, "\x00\x12\x00\x34\x00\x56\x00\x78", 4, 2, 8, BIG_ENDIAN))
    end

    def test_unpack_sign
      assert_equal(-1, Integer.test_unpack(-1, "\x01", 1, 1, 0, BIG_ENDIAN))
      assert_equal(-0x8070605040302010, Integer.test_unpack(-1, "\x80\x70\x60\x50\x40\x30\x20\x10", 8, 1, 0, BIG_ENDIAN))
    end

  end
end
