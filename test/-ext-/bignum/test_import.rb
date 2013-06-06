# coding: ASCII-8BIT

require 'test/unit'
require "-test-/bignum"

class TestBignum < Test::Unit::TestCase
  class TestImport < Test::Unit::TestCase
    def test_import_zero
      assert_equal(0, Integer.test_import(0, "", 1, 1, 1, 1, 0))
    end

    def test_argument_check
      assert_raise(ArgumentError) { Integer.test_import(1, "x", 1, 0, 1, 1, 0) }
      assert_raise(ArgumentError) { Integer.test_import(1, "x", 1, 1, 1, 2, 0) }
      assert_raise(ArgumentError) { Integer.test_import(1, "x", 1, 1, 0, 1, 0) }
      assert_raise(ArgumentError) { Integer.test_import(1, "x", 1, 1, 1, 1, 8) }

      # assume sizeof(ssize_t) == sizeof(intptr_t)
      assert_raise(ArgumentError) { Integer.test_import(1, "x", 1, 1, 1 << ([""].pack("p").length * 8 - 1), 1, 0) }
    end

    def test_import_wordsize
      assert_equal(1, Integer.test_import(1, "\x01", 1, 1, 1, 1, 0))
      assert_equal(1, Integer.test_import(1, "\x00\x01", 1, 1, 2, 1, 0))
      assert_equal(1, Integer.test_import(1, "\x00\x00\x01", 1, 1, 3, 1, 0))
      assert_equal(1, Integer.test_import(1, "\x01", 1, 1, 1, -1, 0))
      assert_equal(1, Integer.test_import(1, "\x01\x00", 1, 1, 2, -1, 0))
      assert_equal(1, Integer.test_import(1, "\x01\x00\x00", 1, 1, 3, -1, 0))
    end

    def test_import_wordorder_and_endian
      assert_equal(0x01020304, Integer.test_import(1, "\x01\x02\x03\x04", 2, 1, 2, 1, 0))
      assert_equal(0x02010403, Integer.test_import(1, "\x01\x02\x03\x04", 2, 1, 2, -1, 0))
      assert_equal(0x03040102, Integer.test_import(1, "\x01\x02\x03\x04", 2, -1, 2, 1, 0))
      assert_equal(0x04030201, Integer.test_import(1, "\x01\x02\x03\x04", 2, -1, 2, -1, 0))
    end

    def test_import_native_endian
      assert_equal("\x12\x34".unpack("S!")[0], Integer.test_import(1, "\x12\x34", 1, 1, 2, 0, 0))
    end

    def test_import_nail
      assert_equal(0b100011, Integer.test_import(1, "\x01\x00\x00\x00\x01\x01", 6, 1, 1, 1, 7))
      assert_equal(0x12345678, Integer.test_import(1, "\x01\x02\x03\x04\x05\x06\x07\x08", 8, 1, 1, 1, 4))
      assert_equal(0x12345678, Integer.test_import(1, "\x00\x12\x00\x34\x00\x56\x00\x78", 4, 1, 2, 1, 8))
    end

    def test_import_sign
      assert_equal(-1, Integer.test_import(-1, "\x01", 1, 1, 1, 1, 0))
      assert_equal(-0x8070605040302010, Integer.test_import(-1, "\x80\x70\x60\x50\x40\x30\x20\x10", 8, 1, 1, 1, 0))
    end

  end
end
