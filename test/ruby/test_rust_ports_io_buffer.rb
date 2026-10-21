# frozen_string_literal: false
require 'test/unit'

# Ruby on Rust: io_buffer.c's memory_or_inplace, memory_xor_inplace,
# memory_not_inplace and memory_bit_count are ported to
# core_rs/src/io_buffer.rs (port unit io_buffer-A-03).  They are reached
# through IO::Buffer#or!, #xor!, #not! and #bit_count.
#
# These tests must pass unchanged in both build modes:
#   ./configure                         (Rust ports, USE_RUST_PORTS=1)
#   ./configure --without-rust-ports    (original C, USE_RUST_PORTS=0)
# The non-in-place operators (#|, #^, #~) are still C in both modes and
# serve as an independent reference for the in-place results.
class TestRustPortsIOBuffer < Test::Unit::TestCase
  def buffer(string)
    IO::Buffer.for(string.b).dup
  end

  def bytes(buf)
    buf.get_string.b
  end

  def naive_cyclic(source, mask, op)
    source.bytes.each_with_index.map { |b, i| b.public_send(op, mask.getbyte(i % mask.bytesize)) }.pack("C*")
  end

  def test_or_inplace_documented_example
    source = buffer("1234567890")
    assert_same source, source.or!(IO::Buffer.for("\xFF\x00\x00\xFF"))
    assert_equal "\xff23\xff\xff67\xff\xff0".b, bytes(source)
  end

  def test_xor_inplace_documented_example
    source = buffer("1234567890")
    assert_same source, source.xor!(IO::Buffer.for("\xFF\x00\x00\xFF"))
    assert_equal "\xce23\xcb\xca67\xc7\xc60".b, bytes(source)
  end

  def test_not_inplace_documented_example
    source = buffer("1234567890")
    assert_same source, source.not!
    assert_equal "\xce\xcd\xcc\xcb\xca\xc9\xc8\xc7\xc6\xcf".b, bytes(source)
    source.not!
    assert_equal "1234567890", bytes(source)
  end

  def test_mask_is_applied_cyclically
    data = (0...37).map { |i| (i * 73 + 11) & 0xff }.pack("C*")
    [1, 2, 3, 7, 8, 9, 36, 37, 38, 100].each do |mask_len|
      mask = (0...mask_len).map { |i| (i * 151 + 5) & 0xff }.pack("C*")
      mask_buffer = IO::Buffer.for(mask)
      assert_equal naive_cyclic(data, mask, :|), bytes(buffer(data).or!(mask_buffer)), "or! mask_len=#{mask_len}"
      assert_equal naive_cyclic(data, mask, :^), bytes(buffer(data).xor!(mask_buffer)), "xor! mask_len=#{mask_len}"
      assert_equal bytes(IO::Buffer.for(data) | mask_buffer), bytes(buffer(data).or!(mask_buffer))
      assert_equal bytes(IO::Buffer.for(data) ^ mask_buffer), bytes(buffer(data).xor!(mask_buffer))
      assert_equal mask, mask_buffer.get_string.b, "mask must not be modified"
    end
  end

  def test_not_inplace_matches_operator
    data = (0..255).to_a.pack("C*")
    assert_equal bytes(~IO::Buffer.for(data)), bytes(buffer(data).not!)
    assert_equal data.bytes.map { |b| b ^ 0xff }.pack("C*"), bytes(buffer(data).not!)
  end

  def test_inplace_operators_on_slices_touch_only_the_slice
    whole = IO::Buffer.new(12)
    whole.set_string("abcdefghijkl")
    mask = IO::Buffer.for("\x20")
    whole.slice(2, 4).xor!(mask)
    assert_equal "abCDEFghijkl", whole.get_string
    whole.slice(2, 4).or!(mask)
    assert_equal "abcdefghijkl", whole.get_string
    whole.slice(8, 2).not!
    assert_equal "abcdefgh\x96\x95kl".b, whole.get_string.b
  ensure
    whole&.free
  end

  def test_inplace_operators_on_empty_buffers
    empty = IO::Buffer.new(0)
    assert_same empty, empty.or!(IO::Buffer.for("x"))
    assert_same empty, empty.xor!(IO::Buffer.for("x"))
    assert_same empty, empty.not!
    assert_equal 0, empty.bit_count
  end

  def test_bit_count_every_length_and_offset
    data = (0...40).map { |i| (i * 97 + 31) & 0xff }.pack("C*")
    buf = IO::Buffer.for(data)
    (0..data.bytesize).each do |offset|
      (0..(data.bytesize - offset)).each do |length|
        expected = data.byteslice(offset, length).unpack1("B*").count("1")
        assert_equal expected, buf.bit_count(offset, length), "offset=#{offset} length=#{length}"
      end
    end
  end

  def test_bit_count_values
    assert_equal 12, IO::Buffer.for("\xFF\x00\x0F").bit_count
    assert_equal 4, IO::Buffer.for("\xFF\x00\x0F").bit_count(1, 2)
    assert_equal 64, IO::Buffer.for("\xFF" * 8).bit_count
    assert_equal 71, IO::Buffer.for("\xFF" * 8 + "\xFE").bit_count
    assert_equal 4096 * 8, IO::Buffer.for("\xFF" * 4096).bit_count
    assert_equal 0, IO::Buffer.for("\x00" * 4097).bit_count
    assert_equal 0, IO::Buffer.for("\xFF").bit_count(1, 0)
  end
end
