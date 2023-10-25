begin
  require_relative 'helper'
  require 'fiddle/pack'
rescue LoadError
  return
end

module Fiddle
  class TestPack < TestCase
    def test_pack_map
      if defined?(TYPE_LONG_LONG)
        assert_equal [0xffff_ffff_ffff_ffff], [0xffff_ffff_ffff_ffff].pack(PackInfo::PACK_MAP[-TYPE_LONG_LONG]).unpack(PackInfo::PACK_MAP[-TYPE_LONG_LONG])
      end

      case Fiddle::SIZEOF_VOIDP
      when 8
        assert_equal [0xffff_ffff_ffff_ffff], [0xffff_ffff_ffff_ffff].pack(PackInfo::PACK_MAP[TYPE_VOIDP]).unpack(PackInfo::PACK_MAP[TYPE_VOIDP])
      when 4
        assert_equal [0xffff_ffff], [0xffff_ffff].pack(PackInfo::PACK_MAP[TYPE_VOIDP]).unpack(PackInfo::PACK_MAP[TYPE_VOIDP])
      end

      case Fiddle::SIZEOF_LONG
      when 8
        assert_equal [0xffff_ffff_ffff_ffff], [0xffff_ffff_ffff_ffff].pack(PackInfo::PACK_MAP[-TYPE_LONG]).unpack(PackInfo::PACK_MAP[-TYPE_LONG])
      when 4
        assert_equal [0xffff_ffff], [0xffff_ffff].pack(PackInfo::PACK_MAP[-TYPE_LONG]).unpack(PackInfo::PACK_MAP[-TYPE_LONG])
      end

      if Fiddle::SIZEOF_INT == 4
        assert_equal [0xffff_ffff], [0xffff_ffff].pack(PackInfo::PACK_MAP[-TYPE_INT]).unpack(PackInfo::PACK_MAP[-TYPE_INT])
      end

      assert_equal [0xffff], [0xffff].pack(PackInfo::PACK_MAP[-TYPE_SHORT]).unpack(PackInfo::PACK_MAP[-TYPE_SHORT])
      assert_equal [0xff], [0xff].pack(PackInfo::PACK_MAP[-TYPE_CHAR]).unpack(PackInfo::PACK_MAP[-TYPE_CHAR])
    end
  end
end
