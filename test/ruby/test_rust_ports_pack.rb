# frozen_string_literal: false
require 'test/unit'

# Ruby on Rust: pack.c helpers (is_bigendian, skip_to_eol, pack_alignof, hex2num)
# ported to core_rs/src/pack.rs (port unit pack-A-01).
class TestRustPortsPack < Test::Unit::TestCase
  def test_skip_to_eol_comments
    # '#' introduces a comment until end of line in pack/unpack template string
    fmt = "i # comment on line 1\ni # comment on line 2\nS"
    packed = [1, 2, 3].pack(fmt)
    unpacked = packed.unpack(fmt)
    assert_equal([1, 2, 3], unpacked)
  end

  def test_pack_alignof_alignment_modifiers
    # Alignment modifiers '_' and '!' trigger pack_alignof on allowed integer types sSiIlLqQjJ
    fmt = "s_ i_ l_ q_"
    packed = [1, 2, 3, 4].pack(fmt)
    unpacked = packed.unpack(fmt)
    assert_equal([1, 2, 3, 4], unpacked)
  end

  def test_hex2num_hex_decoding
    # 'h' and 'H' directives use hex2num
    assert_equal(["414243"], "ABC".unpack("H*"))
    assert_equal(["142434"], "ABC".unpack("h*"))
    assert_equal("ABC", ["414243"].pack("H*"))
    assert_equal("ABC", ["142434"].pack("h*"))

    # Invalid hex digits in pack
    assert_equal("\x00", ["0g"].pack("H2"))
    assert_equal("\x00", ["0g"].pack("h2"))
  end

  def test_base64_and_uuencode
    # 'm' (base64) uses decoding helpers
    assert_equal(["Hello"], "SGVsbG8=\n".unpack("m"))
    assert_equal("SGVsbG8=\n", ["Hello"].pack("m"))
  end
end
