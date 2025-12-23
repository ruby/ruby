# frozen_string_literal: false

require 'tempfile'
require 'rbconfig/sizeof'

class TestIOBuffer < Test::Unit::TestCase
  experimental = Warning[:experimental]
  begin
    Warning[:experimental] = false
    IO::Buffer.new(0)
  ensure
    Warning[:experimental] = experimental
  end

  def assert_negative(value)
    assert(value < 0, "Expected #{value} to be negative!")
  end

  def assert_positive(value)
    assert(value > 0, "Expected #{value} to be positive!")
  end

  def test_flags
    assert_equal 1, IO::Buffer::EXTERNAL
    assert_equal 2, IO::Buffer::INTERNAL
    assert_equal 4, IO::Buffer::MAPPED

    assert_equal 32, IO::Buffer::LOCKED
    assert_equal 64, IO::Buffer::PRIVATE

    assert_equal 128, IO::Buffer::READONLY
  end

  def test_endian
    assert_equal 4, IO::Buffer::LITTLE_ENDIAN
    assert_equal 8, IO::Buffer::BIG_ENDIAN
    assert_equal 8, IO::Buffer::NETWORK_ENDIAN

    assert_include [IO::Buffer::LITTLE_ENDIAN, IO::Buffer::BIG_ENDIAN], IO::Buffer::HOST_ENDIAN
  end

  def test_default_size
    assert_equal IO::Buffer::DEFAULT_SIZE, IO::Buffer.new.size
  end

  def test_new_internal
    buffer = IO::Buffer.new(1024, IO::Buffer::INTERNAL)
    assert_equal 1024, buffer.size
    refute buffer.external?
    assert buffer.internal?
    refute buffer.mapped?
  end

  def test_new_mapped
    buffer = IO::Buffer.new(1024, IO::Buffer::MAPPED)
    assert_equal 1024, buffer.size
    refute buffer.external?
    refute buffer.internal?
    assert buffer.mapped?
  end

  def test_new_readonly
    buffer = IO::Buffer.new(128, IO::Buffer::INTERNAL|IO::Buffer::READONLY)
    assert buffer.readonly?

    assert_raise IO::Buffer::AccessError do
      buffer.set_string("")
    end

    assert_raise IO::Buffer::AccessError do
      buffer.set_string("!", 1)
    end
  end

  def test_file_mapped
    buffer = File.open(__FILE__) {|file| IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY)}
    assert_equal File.size(__FILE__), buffer.size

    contents = buffer.get_string
    assert_include contents, "Hello World"
    assert_equal Encoding::BINARY, contents.encoding
  end

  def test_file_mapped_with_size
    buffer = File.open(__FILE__) {|file| IO::Buffer.map(file, 30, 0, IO::Buffer::READONLY)}
    assert_equal 30, buffer.size

    contents = buffer.get_string
    assert_equal "# frozen_string_literal: false", contents
    assert_equal Encoding::BINARY, contents.encoding
  end

  def test_file_mapped_size_too_large
    assert_raise ArgumentError do
      File.open(__FILE__) {|file| IO::Buffer.map(file, 200_000, 0, IO::Buffer::READONLY)}
    end
    assert_raise ArgumentError do
      File.open(__FILE__) {|file| IO::Buffer.map(file, File.size(__FILE__) + 1, 0, IO::Buffer::READONLY)}
    end
  end

  def test_file_mapped_size_just_enough
    File.open(__FILE__) {|file|
      assert_equal File.size(__FILE__), IO::Buffer.map(file, File.size(__FILE__), 0, IO::Buffer::READONLY).size
    }
  end

  def test_file_mapped_offset_too_large
    assert_raise ArgumentError do
      File.open(__FILE__) {|file| IO::Buffer.map(file, nil, IO::Buffer::PAGE_SIZE * 100, IO::Buffer::READONLY)}
    end
    assert_raise ArgumentError do
      File.open(__FILE__) {|file| IO::Buffer.map(file, 20, IO::Buffer::PAGE_SIZE * 100, IO::Buffer::READONLY)}
    end
  end

  def test_file_mapped_zero_size
    assert_raise ArgumentError do
      File.open(__FILE__) {|file| IO::Buffer.map(file, 0, 0, IO::Buffer::READONLY)}
    end
  end

  def test_file_mapped_negative_size
    assert_raise ArgumentError do
      File.open(__FILE__) {|file| IO::Buffer.map(file, -10, 0, IO::Buffer::READONLY)}
    end
  end

  def test_file_mapped_negative_offset
    assert_raise ArgumentError do
      File.open(__FILE__) {|file| IO::Buffer.map(file, 20, -1, IO::Buffer::READONLY)}
    end
  end

  def test_file_mapped_invalid
    assert_raise TypeError do
      IO::Buffer.map("foobar")
    end
  end

  def test_string_mapped
    string = "Hello World"
    buffer = IO::Buffer.for(string)
    assert buffer.readonly?
  end

  def test_string_mapped_frozen
    string = "Hello World".freeze
    buffer = IO::Buffer.for(string)
    assert buffer.readonly?
  end

  def test_string_mapped_mutable
    string = "Hello World"
    IO::Buffer.for(string) do |buffer|
      refute buffer.readonly?

      buffer.set_value(:U8, 0, "h".ord)

      # Buffer releases it's ownership of the string:
      buffer.free

      assert_equal "hello World", string
    end
  end

  def test_string_mapped_buffer_locked
    string = "Hello World"
    IO::Buffer.for(string) do |buffer|
      # Cannot modify string as it's locked by the buffer:
      assert_raise RuntimeError do
        string[0] = "h"
      end
    end
  end

  def test_string_mapped_buffer_frozen
    string = "Hello World".freeze
    IO::Buffer.for(string) do |buffer|
      assert_raise IO::Buffer::AccessError, "Buffer is not writable!" do
        buffer.set_string("abc")
      end
      assert_equal "H".ord, buffer.get_value(:U8, 0)
    end
  end

  def test_non_string
    not_string = Object.new

    assert_raise TypeError do
      IO::Buffer.for(not_string)
    end
  end

  def test_string
    result = IO::Buffer.string(12) do |buffer|
      buffer.set_string("Hello World!")
    end

    assert_equal "Hello World!", result
  end

  def test_string_negative
    assert_raise ArgumentError do
      IO::Buffer.string(-1)
    end
  end

  def test_resize_mapped
    buffer = IO::Buffer.new

    buffer.resize(2048)
    assert_equal 2048, buffer.size

    buffer.resize(4096)
    assert_equal 4096, buffer.size
  end

  def test_resize_preserve
    message = "Hello World"
    buffer = IO::Buffer.new(1024)
    buffer.set_string(message)
    buffer.resize(2048)
    assert_equal message, buffer.get_string(0, message.bytesize)
  end

  def test_resize_zero_internal
    buffer = IO::Buffer.new(1)

    buffer.resize(0)
    assert_equal 0, buffer.size

    buffer.resize(1)
    assert_equal 1, buffer.size
  end

  def test_resize_zero_external
    buffer = IO::Buffer.for('1')

    assert_raise IO::Buffer::AccessError do
      buffer.resize(0)
    end
  end

  def test_compare_same_size
    buffer1 = IO::Buffer.new(1)
    assert_equal buffer1, buffer1

    buffer2 = IO::Buffer.new(1)
    buffer1.set_value(:U8, 0, 0x10)
    buffer2.set_value(:U8, 0, 0x20)

    assert_negative buffer1 <=> buffer2
    assert_positive buffer2 <=> buffer1
  end

  def test_compare_different_size
    buffer1 = IO::Buffer.new(3)
    buffer2 = IO::Buffer.new(5)

    assert_negative buffer1 <=> buffer2
    assert_positive buffer2 <=> buffer1
  end

  def test_compare_zero_length
    buffer1 = IO::Buffer.new(0)
    buffer2 = IO::Buffer.new(1)

    assert_negative buffer1 <=> buffer2
    assert_positive buffer2 <=> buffer1
  end

  def test_slice
    buffer = IO::Buffer.new(128)
    slice = buffer.slice(8, 32)
    slice.set_string("Hello World")
    assert_equal("Hello World", buffer.get_string(8, 11))
  end

  def test_slice_arguments
    buffer = IO::Buffer.for("Hello World")

    slice = buffer.slice
    assert_equal "Hello World", slice.get_string

    slice = buffer.slice(2)
    assert_equal("llo World", slice.get_string)
  end

  def test_slice_bounds_error
    buffer = IO::Buffer.new(128)

    assert_raise ArgumentError do
      buffer.slice(128, 10)
    end

    assert_raise ArgumentError do
      buffer.slice(-10, 10)
    end
  end

  def test_slice_readonly
    hello = %w"Hello World".join(" ").freeze
    buffer = IO::Buffer.for(hello)
    slice = buffer.slice
    assert_predicate slice, :readonly?
    assert_raise IO::Buffer::AccessError do
      # This breaks the literal in string pool and many other tests in this file.
      slice.set_string("Adios", 0, 5)
    end
    assert_equal "Hello World", hello
  end

  def test_transfer
    hello = %w"Hello World".join(" ")
    buffer = IO::Buffer.for(hello)
    transferred = buffer.transfer
    assert_equal "Hello World", transferred.get_string
    assert_predicate buffer, :null?
    assert_raise IO::Buffer::AccessError do
      transferred.set_string("Goodbye")
    end
    assert_equal "Hello World", hello
  end

  def test_transfer_in_block
    hello = %w"Hello World".join(" ")
    buffer = IO::Buffer.for(hello, &:transfer)
    assert_equal "Hello World", buffer.get_string
    buffer.set_string("Ciao!")
    assert_equal "Ciao! World", hello
    hello.freeze
    assert_raise IO::Buffer::AccessError do
      buffer.set_string("Hola")
    end
    assert_equal "Ciao! World", hello
  end

  def test_locked
    buffer = IO::Buffer.new(128, IO::Buffer::INTERNAL|IO::Buffer::LOCKED)

    assert_raise IO::Buffer::LockedError do
      buffer.resize(256)
    end

    assert_equal 128, buffer.size

    assert_raise IO::Buffer::LockedError do
      buffer.free
    end

    assert_equal 128, buffer.size
  end

  def test_get_string
    message = "Hello World 🤓"

    buffer = IO::Buffer.new(128)
    buffer.set_string(message)

    chunk = buffer.get_string(0, message.bytesize, Encoding::UTF_8)
    assert_equal message, chunk
    assert_equal Encoding::UTF_8, chunk.encoding

    chunk = buffer.get_string(0, message.bytesize, Encoding::BINARY)
    assert_equal Encoding::BINARY, chunk.encoding

    assert_raise_with_message(ArgumentError, /bigger than the buffer size/) do
      buffer.get_string(0, 129)
    end

    assert_raise_with_message(ArgumentError, /bigger than the buffer size/) do
      buffer.get_string(129)
    end

    assert_raise_with_message(ArgumentError, /Offset can't be negative/) do
      buffer.get_string(-1)
    end
  end

  def test_zero_length_get_string
    buffer = IO::Buffer.new.slice(0, 0)
    assert_equal "", buffer.get_string

    buffer = IO::Buffer.new(0)
    assert_equal "", buffer.get_string
  end

  # We check that values are correctly round tripped.
  RANGES = {
    :U8 => [0, 2**8-1],
    :S8 => [-2**7, 0, 2**7-1],

    :U16 => [0, 2**16-1],
    :S16 => [-2**15, 0, 2**15-1],
    :u16 => [0, 2**16-1],
    :s16 => [-2**15, 0, 2**15-1],

    :U32 => [0, 2**32-1],
    :S32 => [-2**31, 0, 2**31-1],
    :u32 => [0, 2**32-1],
    :s32 => [-2**31, 0, 2**31-1],

    :U64 => [0, 2**64-1],
    :S64 => [-2**63, 0, 2**63-1],
    :u64 => [0, 2**64-1],
    :s64 => [-2**63, 0, 2**63-1],

    :U128 => [0, 2**64, 2**127-1, 2**128-1],
    :S128 => [-2**127, -2**63-1, -1, 0, 2**63, 2**127-1],
    :u128 => [0, 2**64, 2**127-1, 2**128-1],
    :s128 => [-2**127, -2**63-1, -1, 0, 2**63, 2**127-1],

    :F32 => [-1.0, 0.0, 0.5, 1.0, 128.0],
    :F64 => [-1.0, 0.0, 0.5, 1.0, 128.0],
  }

  SIZE_MAX = RbConfig::LIMITS["SIZE_MAX"]

  def test_get_set_value
    buffer = IO::Buffer.new(128)

    RANGES.each do |data_type, values|
      values.each do |value|
        buffer.set_value(data_type, 0, value)
        assert_equal value, buffer.get_value(data_type, 0), "Converting #{value} as #{data_type}."
      end
      assert_raise(ArgumentError) {buffer.get_value(data_type, 128)}
      assert_raise(ArgumentError) {buffer.set_value(data_type, 128, 0)}
      case data_type
      when :U8, :S8
      else
        assert_raise(ArgumentError) {buffer.get_value(data_type, 127)}
        assert_raise(ArgumentError) {buffer.set_value(data_type, 127, 0)}
        assert_raise(ArgumentError) {buffer.get_value(data_type, SIZE_MAX)}
        assert_raise(ArgumentError) {buffer.set_value(data_type, SIZE_MAX, 0)}
      end
    end
  end

  def test_get_set_values
    buffer = IO::Buffer.new(128)

    RANGES.each do |data_type, values|
      format = [data_type] * values.size

      buffer.set_values(format, 0, values)
      assert_equal values, buffer.get_values(format, 0), "Converting #{values} as #{format}."
    end
  end

  def test_zero_length_get_set_values
    buffer = IO::Buffer.new(0)

    assert_equal [], buffer.get_values([], 0)
    assert_equal 0, buffer.set_values([], 0, [])
  end

  def test_values
    buffer = IO::Buffer.new(128)

    RANGES.each do |data_type, values|
      format = [data_type] * values.size

      buffer.set_values(format, 0, values)
      assert_equal values, buffer.values(data_type, 0, values.size), "Reading #{values} as #{format}."
    end
  end

  def test_each
    buffer = IO::Buffer.new(128)

    RANGES.each do |data_type, values|
      format = [data_type] * values.size
      data_type_size = IO::Buffer.size_of(data_type)
      values_with_offsets = values.map.with_index{|value, index| [index * data_type_size, value]}

      buffer.set_values(format, 0, values)
      assert_equal values_with_offsets, buffer.each(data_type, 0, values.size).to_a, "Reading #{values} as #{data_type}."
    end
  end

  def test_zero_length_each
    buffer = IO::Buffer.new(0)

    assert_equal [], buffer.each(:U8).to_a
  end

  def test_each_byte
    string = "The quick brown fox jumped over the lazy dog."
    buffer = IO::Buffer.for(string)

    assert_equal string.bytes, buffer.each_byte.to_a
    assert_equal string.bytes[3, 5], buffer.each_byte(3, 5).to_a
  end

  def test_zero_length_each_byte
    buffer = IO::Buffer.new(0)

    assert_equal [], buffer.each_byte.to_a
  end

  def test_clear
    buffer = IO::Buffer.new(16)
    assert_equal "\0" * 16, buffer.get_string
    buffer.clear(1)
    assert_equal "\1" * 16, buffer.get_string
    buffer.clear(2, 1, 2)
    assert_equal "\1" + "\2"*2 + "\1"*13, buffer.get_string
    buffer.clear(2, 1)
    assert_equal "\1" + "\2"*15, buffer.get_string
    buffer.clear(260)
    assert_equal "\4" * 16, buffer.get_string
    assert_raise(TypeError) {buffer.clear("x")}

    assert_raise(ArgumentError) {buffer.clear(0, 20)}
    assert_raise(ArgumentError) {buffer.clear(0, 0, 20)}
    assert_raise(ArgumentError) {buffer.clear(0, 10, 10)}
    assert_raise(ArgumentError) {buffer.clear(0, SIZE_MAX-7, 10)}
  end

  def test_invalidation
    input, output = IO.pipe

    # (1) rb_write_internal creates IO::Buffer object,
    buffer = IO::Buffer.new(128)

    # (2) it is passed to (malicious) scheduler
    # (3) scheduler starts a thread which call system call with the buffer object
    thread = Thread.new{buffer.locked{input.read}}

    Thread.pass until thread.stop?

    # (4) scheduler returns
    # (5) rb_write_internal invalidate the buffer object
    assert_raise IO::Buffer::LockedError do
      buffer.free
    end

    # (6) the system call access the memory area after invalidation
    output.write("Hello World")
    output.close
    thread.join

    input.close
  end

  def hello_world_tempfile(repeats = 1)
    io = Tempfile.new
    repeats.times do
      io.write("Hello World")
    end
    io.seek(0)

    yield io
  ensure
    io&.close!
  end

  def test_read
    hello_world_tempfile do |io|
      buffer = IO::Buffer.new(128)
      buffer.read(io)
      assert_equal "Hello", buffer.get_string(0, 5)
    end
  end

  def test_read_with_with_length
    hello_world_tempfile do |io|
      buffer = IO::Buffer.new(128)
      buffer.read(io, 5)
      assert_equal "Hello", buffer.get_string(0, 5)
    end
  end

  def test_read_with_with_offset
    hello_world_tempfile do |io|
      buffer = IO::Buffer.new(128)
      buffer.read(io, nil, 6)
      assert_equal "Hello", buffer.get_string(6, 5)
    end
  end

  def test_read_with_length_and_offset
    hello_world_tempfile(100) do |io|
      buffer = IO::Buffer.new(1024)
      # Only read 24 bytes from the file, as we are starting at offset 1000 in the buffer.
      assert_equal 24, buffer.read(io, 0, 1000)
      assert_equal "Hello World", buffer.get_string(1000, 11)
    end
  end

  def test_write
    io = Tempfile.new

    buffer = IO::Buffer.new(128)
    buffer.set_string("Hello")
    buffer.write(io)

    io.seek(0)
    assert_equal "Hello", io.read(5)
  ensure
    io.close!
  end

  def test_write_with_length_and_offset
    io = Tempfile.new

    buffer = IO::Buffer.new(5)
    buffer.set_string("Hello")
    buffer.write(io, 4, 1)

    io.seek(0)
    assert_equal "ello", io.read(4)
  ensure
    io.close!
  end

  def test_pread
    io = Tempfile.new
    io.write("Hello World")
    io.seek(0)

    buffer = IO::Buffer.new(128)
    buffer.pread(io, 6, 5)

    assert_equal "World", buffer.get_string(0, 5)
    assert_equal 0, io.tell
  ensure
    io.close!
  end

  def test_pread_offset
    io = Tempfile.new
    io.write("Hello World")
    io.seek(0)

    buffer = IO::Buffer.new(128)
    buffer.pread(io, 6, 5, 6)

    assert_equal "World", buffer.get_string(6, 5)
    assert_equal 0, io.tell
  ensure
    io.close!
  end

  def test_pwrite
    io = Tempfile.new

    buffer = IO::Buffer.new(128)
    buffer.set_string("World")
    buffer.pwrite(io, 6, 5)

    assert_equal 0, io.tell

    io.seek(6)
    assert_equal "World", io.read(5)
  ensure
    io.close!
  end

  def test_pwrite_offset
    io = Tempfile.new

    buffer = IO::Buffer.new(128)
    buffer.set_string("Hello World")
    buffer.pwrite(io, 6, 5, 6)

    assert_equal 0, io.tell

    io.seek(6)
    assert_equal "World", io.read(5)
  ensure
    io.close!
  end

  def test_operators
    source = IO::Buffer.for("1234123412")
    mask = IO::Buffer.for("133\x00")

    assert_equal IO::Buffer.for("123\x00123\x0012"), (source & mask)
    assert_equal IO::Buffer.for("1334133413"), (source | mask)
    assert_equal IO::Buffer.for("\x00\x01\x004\x00\x01\x004\x00\x01"), (source ^ mask)
    assert_equal IO::Buffer.for("\xce\xcd\xcc\xcb\xce\xcd\xcc\xcb\xce\xcd"), ~source
  end

  def test_inplace_operators
    source = IO::Buffer.for("1234123412")
    mask = IO::Buffer.for("133\x00")

    assert_equal IO::Buffer.for("123\x00123\x0012"), source.dup.and!(mask)
    assert_equal IO::Buffer.for("1334133413"), source.dup.or!(mask)
    assert_equal IO::Buffer.for("\x00\x01\x004\x00\x01\x004\x00\x01"), source.dup.xor!(mask)
    assert_equal IO::Buffer.for("\xce\xcd\xcc\xcb\xce\xcd\xcc\xcb\xce\xcd"), source.dup.not!
  end

  def test_shared
    message = "Hello World"
    buffer = IO::Buffer.new(64, IO::Buffer::MAPPED | IO::Buffer::SHARED)

    pid = fork do
      buffer.set_string(message)
    end

    Process.wait(pid)
    string = buffer.get_string(0, message.bytesize)
    assert_equal message, string
  rescue NotImplementedError
    omit "Fork/shared memory is not supported."
  end

  def test_private
    Tempfile.create(%w"buffer .txt") do |file|
      file.write("Hello World")

      buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::PRIVATE)
      begin
        assert buffer.private?
        refute buffer.readonly?

        buffer.set_string("J")

        # It was not changed because the mapping was private:
        file.seek(0)
        assert_equal "Hello World", file.read
      ensure
        buffer&.free
      end
    end
  end

  def test_copy_overlapped_fwd
    buf = IO::Buffer.for('0123456789').dup
    buf.copy(buf, 3, 7)
    assert_equal '0120123456', buf.get_string
  end

  def test_copy_overlapped_bwd
    buf = IO::Buffer.for('0123456789').dup
    buf.copy(buf, 0, 7, 3)
    assert_equal '3456789789', buf.get_string
  end

  def test_copy_null_destination
    buf = IO::Buffer.new(0)
    assert_predicate buf, :null?
    buf.copy(IO::Buffer.for('a'), 0, 0)
    assert_predicate buf, :empty?
  end

  def test_copy_null_source
    buf = IO::Buffer.for('a').dup
    src = IO::Buffer.new(0)
    assert_predicate src, :null?
    buf.copy(src, 0, 0)
    assert_equal 'a', buf.get_string
  end

  def test_set_string_overlapped_fwd
    str = +'0123456789'
    IO::Buffer.for(str) do |buf|
      buf.set_string(str, 3, 7)
    end
    assert_equal '0120123456', str
  end

  def test_set_string_overlapped_bwd
    str = +'0123456789'
    IO::Buffer.for(str) do |buf|
      buf.set_string(str, 0, 7, 3)
    end
    assert_equal '3456789789', str
  end

  def test_set_string_null_destination
    buf = IO::Buffer.new(0)
    assert_predicate buf, :null?
    buf.set_string('a', 0, 0)
    assert_predicate buf, :empty?
  end

  # https://bugs.ruby-lang.org/issues/21210
  def test_bug_21210
    omit "compaction is not supported on this platform" unless GC.respond_to?(:compact)

    str = +"hello"
    buf = IO::Buffer.for(str)
    assert_predicate buf, :valid?

    GC.verify_compaction_references(expand_heap: true, toward: :empty)

    assert_predicate buf, :valid?
  end

  def test_128_bit_integers
    buffer = IO::Buffer.new(32)

    # Test unsigned 128-bit integers
    test_values_u128 = [
      0,
      1,
      2**64 - 1,
      2**64,
      2**127 - 1,
      2**128 - 1,
    ]

    test_values_u128.each do |value|
      buffer.set_value(:u128, 0, value)
      assert_equal value, buffer.get_value(:u128, 0), "u128: #{value}"

      buffer.set_value(:U128, 0, value)
      assert_equal value, buffer.get_value(:U128, 0), "U128: #{value}"
    end

    # Test signed 128-bit integers
    test_values_s128 = [
      -2**127,
      -2**63 - 1,
      -1,
      0,
      1,
      2**63,
      2**127 - 1,
    ]

    test_values_s128.each do |value|
      buffer.set_value(:s128, 0, value)
      assert_equal value, buffer.get_value(:s128, 0), "s128: #{value}"

      buffer.set_value(:S128, 0, value)
      assert_equal value, buffer.get_value(:S128, 0), "S128: #{value}"
    end

    # Test size_of
    assert_equal 16, IO::Buffer.size_of(:u128)
    assert_equal 16, IO::Buffer.size_of(:U128)
    assert_equal 16, IO::Buffer.size_of(:s128)
    assert_equal 16, IO::Buffer.size_of(:S128)
    assert_equal 32, IO::Buffer.size_of([:u128, :u128])
  end

  def test_integer_endianness_swapping
    # Test that byte order is swapped correctly for all signed and unsigned integers > 1 byte
    host_is_le = IO::Buffer::HOST_ENDIAN == IO::Buffer::LITTLE_ENDIAN
    host_is_be = IO::Buffer::HOST_ENDIAN == IO::Buffer::BIG_ENDIAN

    # Test values that will produce different byte patterns when swapped
    # Format: [little_endian_type, big_endian_type, test_value, expected_swapped_value]
    # expected_swapped_value is the result when writing as le_type and reading as be_type
    # (or vice versa) on a little-endian host
    test_cases = [
      [:u16, :U16, 0x1234, 0x3412],
      [:s16, :S16, 0x1234, 0x3412],
      [:u32, :U32, 0x12345678, 0x78563412],
      [:s32, :S32, 0x12345678, 0x78563412],
      [:u64, :U64, 0x0123456789ABCDEF, 0xEFCDAB8967452301],
      [:s64, :S64, 0x0123456789ABCDEF, -1167088121787636991],
      [:u128, :U128, 0x0123456789ABCDEF0123456789ABCDEF, 0xEFCDAB8967452301EFCDAB8967452301],
      [:u128, :U128, 0x0123456789ABCDEFFEDCBA9876543210, 0x1032547698BADCFEEFCDAB8967452301],
      [:u128, :U128, 0xFEDCBA98765432100123456789ABCDEF, 0xEFCDAB89674523011032547698BADCFE],
      [:u128, :U128, 0x123456789ABCDEF0FEDCBA9876543210, 0x1032547698BADCFEF0DEBC9A78563412],
      [:s128, :S128, 0x0123456789ABCDEF0123456789ABCDEF, -21528975894082904073953971026863512831],
      [:s128, :S128, 0x0123456789ABCDEFFEDCBA9876543210, 0x1032547698BADCFEEFCDAB8967452301],
    ]

    test_cases.each do |le_type, be_type, value, expected_swapped|
      buffer_size = IO::Buffer.size_of(le_type)
      buffer = IO::Buffer.new(buffer_size * 2)

      # Test little-endian round-trip
      buffer.set_value(le_type, 0, value)
      result_le = buffer.get_value(le_type, 0)
      assert_equal value, result_le, "#{le_type}: round-trip failed"

      # Test big-endian round-trip
      buffer.set_value(be_type, buffer_size, value)
      result_be = buffer.get_value(be_type, buffer_size)
      assert_equal value, result_be, "#{be_type}: round-trip failed"

      # Verify byte patterns are different when endianness differs from host
      if host_is_le
        # On little-endian host: le_type should match host, be_type should be swapped
        # So the byte patterns should be different (unless value is symmetric)
        # Read back with opposite endianness to verify swapping
        result_le_read_as_be = buffer.get_value(be_type, 0)
        result_be_read_as_le = buffer.get_value(le_type, buffer_size)

        # The swapped reads should NOT equal the original value (unless it's symmetric)
        # For most values, this will be different
        if value != 0 && value != -1 && value.abs != 1
          refute_equal value, result_le_read_as_be, "#{le_type} written, read as #{be_type} should be swapped on LE host"
          refute_equal value, result_be_read_as_le, "#{be_type} written, read as #{le_type} should be swapped on LE host"
        end

        # Verify that reading back with correct endianness works
        assert_equal value, buffer.get_value(le_type, 0), "#{le_type} should read correctly on LE host"
        assert_equal value, buffer.get_value(be_type, buffer_size), "#{be_type} should read correctly on LE host (with swapping)"
      elsif host_is_be
        # On big-endian host: be_type should match host, le_type should be swapped
        result_le_read_as_be = buffer.get_value(be_type, 0)
        result_be_read_as_le = buffer.get_value(le_type, buffer_size)

        # The swapped reads should NOT equal the original value (unless it's symmetric)
        if value != 0 && value != -1 && value.abs != 1
          refute_equal value, result_le_read_as_be, "#{le_type} written, read as #{be_type} should be swapped on BE host"
          refute_equal value, result_be_read_as_le, "#{be_type} written, read as #{le_type} should be swapped on BE host"
        end

        # Verify that reading back with correct endianness works
        assert_equal value, buffer.get_value(be_type, buffer_size), "#{be_type} should read correctly on BE host"
        assert_equal value, buffer.get_value(le_type, 0), "#{le_type} should read correctly on BE host (with swapping)"
      end

      # Verify that when we write with one endianness and read with the opposite,
      # we get the expected swapped value
      buffer.set_value(le_type, 0, value)
      swapped_value_le_to_be = buffer.get_value(be_type, 0)
      assert_equal expected_swapped, swapped_value_le_to_be, "#{le_type} written, read as #{be_type} should produce expected swapped value"

      # Also verify the reverse direction
      buffer.set_value(be_type, buffer_size, value)
      swapped_value_be_to_le = buffer.get_value(le_type, buffer_size)
      assert_equal expected_swapped, swapped_value_be_to_le, "#{be_type} written, read as #{le_type} should produce expected swapped value"

      # Verify that writing the swapped value back and reading with original endianness
      # gives us the original value (double-swap should restore original)
      buffer.set_value(be_type, 0, swapped_value_le_to_be)
      round_trip_value = buffer.get_value(le_type, 0)
      assert_equal value, round_trip_value, "#{le_type}/#{be_type}: double-swap should restore original value"
    end
  end
end
