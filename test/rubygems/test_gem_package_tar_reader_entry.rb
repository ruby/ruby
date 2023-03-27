# frozen_string_literal: true

require_relative "package/tar_test_case"
require "rubygems/package"

class TestGemPackageTarReaderEntry < Gem::Package::TarTestCase
  def setup
    super

    @contents = ("a".."z").to_a.join * 100

    @tar = String.new
    @tar << tar_file_header("lib/foo", "", 0, @contents.size, Time.now)
    @tar << tar_file_contents(@contents)

    @entry = util_entry @tar
  end

  def teardown
    close_util_entry(@entry)
    super
  end

  def test_open
    io = TempIO.new @tar
    header = Gem::Package::TarHeader.from io
    retval = Gem::Package::TarReader::Entry.open header, io, &:getc
    assert_equal "a", retval
    assert_equal @tar.size, io.pos, "should have read to end of entry"
  ensure
    io&.close!
  end

  def test_open_closes_entry
    io = TempIO.new @tar
    header = Gem::Package::TarHeader.from io
    entry = nil
    Gem::Package::TarReader::Entry.open header, io do |e|
      entry = e
    end
    assert entry.closed?
    assert_raise(IOError) { entry.getc }
  ensure
    io&.close!
  end

  def test_open_returns_entry
    io = TempIO.new @tar
    header = Gem::Package::TarHeader.from io
    entry = Gem::Package::TarReader::Entry.open header, io
    refute entry.closed?
    assert_equal "a", entry.getc
    assert_nil entry.close
    assert entry.closed?
  ensure
    io&.close!
  end

  def test_bytes_read
    assert_equal 0, @entry.bytes_read

    @entry.getc

    assert_equal 1, @entry.bytes_read
  end

  def test_size
    assert_equal @contents.size, @entry.size
  end

  def test_close
    @entry.close

    assert @entry.bytes_read

    e = assert_raise(IOError) { @entry.eof? }
    assert_equal "closed Gem::Package::TarReader::Entry", e.message

    e = assert_raise(IOError) { @entry.getc }
    assert_equal "closed Gem::Package::TarReader::Entry", e.message

    e = assert_raise(IOError) { @entry.pos }
    assert_equal "closed Gem::Package::TarReader::Entry", e.message

    e = assert_raise(IOError) { @entry.read }
    assert_equal "closed Gem::Package::TarReader::Entry", e.message

    e = assert_raise(IOError) { @entry.rewind }
    assert_equal "closed Gem::Package::TarReader::Entry", e.message
  end

  def test_closed_eh
    @entry.close

    assert @entry.closed?
  end

  def test_eof_eh
    @entry.read

    assert @entry.eof?
  end

  def test_full_name
    assert_equal "lib/foo", @entry.full_name
  end

  def test_full_name_null
    pend "jruby strips the null byte and does not think it's corrupt" if Gem.java_platform?
    @entry.header.prefix << "\000"

    e = assert_raise Gem::Package::TarInvalidError do
      @entry.full_name
    end

    assert_equal "tar is corrupt, name contains null byte", e.message
  end

  def test_getc
    assert_equal "a", @entry.getc
  end

  def test_directory_eh
    assert_equal false, @entry.directory?
    dir_ent = util_dir_entry
    assert_equal true, dir_ent.directory?
  ensure
    close_util_entry(dir_ent) if dir_ent
  end

  def test_symlink_eh
    assert_equal false, @entry.symlink?
    symlink_ent = util_symlink_entry
    assert_equal true, symlink_ent.symlink?
  ensure
    close_util_entry(symlink_ent) if symlink_ent
  end

  def test_file_eh
    assert_equal true, @entry.file?
    dir_ent = util_dir_entry
    assert_equal false, dir_ent.file?
  ensure
    close_util_entry(dir_ent) if dir_ent
  end

  def test_pos
    assert_equal 0, @entry.pos

    @entry.getc

    assert_equal 1, @entry.pos
  end

  def test_read
    assert_equal @contents, @entry.read
  end

  def test_consecutive_read
    expected = StringIO.new(@contents)
    assert_equal expected.read, @entry.read
    assert_equal expected.read, @entry.read
  end

  def test_consecutive_read_bytes_past_eof
    expected = StringIO.new(@contents)
    assert_equal expected.read, @entry.read
    assert_equal expected.read(1), @entry.read(1)
  end

  def test_read_big
    assert_equal @contents, @entry.read(@contents.size * 2)
  end

  def test_read_small
    assert_equal @contents[0...100], @entry.read(100)
  end

  def test_read_remaining
    @entry.read(100)
    assert_equal @contents[100..-1], @entry.read
  end

  def test_read_partial
    assert_equal @contents[0...100], @entry.readpartial(100)
  end

  def test_read_partial_buffer
    buffer = "".b
    @entry.readpartial(100, buffer)
    assert_equal @contents[0...100], buffer
  end

  def test_readpartial_past_eof
    @entry.readpartial(@contents.size)
    assert_raise(EOFError) do
      @entry.readpartial(1)
    end
  end

  def test_rewind
    char = @entry.getc

    @entry.rewind

    assert_equal 0, @entry.pos

    assert_equal char, @entry.getc
  end

  def test_seek
    @entry.seek(50)
    assert_equal 50, @entry.pos
    assert_equal @contents[50..-1], @entry.read, "read remaining after seek"
    @entry.seek(-50, IO::SEEK_CUR)
    assert_equal @contents.size - 50, @entry.pos
    assert_equal @contents[-50..-1], @entry.read, "read after stepping back 50 from the end"
    @entry.seek(0, IO::SEEK_SET)
    assert_equal 0, @entry.pos
    assert_equal @contents, @entry.read, "read from beginning"
    @entry.seek(-10, IO::SEEK_END)
    assert_equal @contents.size - 10, @entry.pos
    assert_equal @contents[-10..-1], @entry.read, "read from end"
  end

  def test_read_zero
    expected = StringIO.new("")
    assert_equal expected.read(0), @entry.read(0)
  end

  def test_readpartial_zero
    expected = StringIO.new("")
    assert_equal expected.readpartial(0), @entry.readpartial(0)
  end

  def test_zero_byte_file_read
    zero_entry = util_entry(tar_file_header("foo", "", 0, 0, Time.now))
    expected = StringIO.new("")
    assert_equal expected.read, zero_entry.read
  ensure
    close_util_entry(zero_entry) if zero_entry
  end

  def test_zero_byte_file_readpartial
    zero_entry = util_entry(tar_file_header("foo", "", 0, 0, Time.now))
    expected = StringIO.new("")
    assert_equal expected.readpartial(0), zero_entry.readpartial(0)
  ensure
    close_util_entry(zero_entry) if zero_entry
  end

  def test_read_from_gzip_io
    tgz = util_gzip(@tar)

    Zlib::GzipReader.wrap StringIO.new(tgz) do |gzio|
      entry = util_entry(gzio)
      assert_equal @contents, entry.read
      entry.rewind
      assert_equal @contents, entry.read, "second read after rewind should read same contents"
    end
  end

  def test_read_from_gzip_io_with_non_zero_offset
    contents2 = ("0".."9").to_a.join * 100
    @tar << tar_file_header("lib/bar", "", 0, contents2.size, Time.now)
    @tar << tar_file_contents(contents2)

    tgz = util_gzip(@tar)

    Zlib::GzipReader.wrap StringIO.new(tgz) do |gzio|
      util_entry(gzio).close # skip the first entry so io.pos is not 0, preventing easy rewind
      entry = util_entry(gzio)

      assert_equal contents2, entry.read
      entry.rewind
      assert_equal contents2, entry.read, "second read after rewind should read same contents"
    end
  end

  def test_seek_in_gzip_io_with_non_zero_offset
    contents2 = ("0".."9").to_a.join * 100
    @tar << tar_file_header("lib/bar", "", 0, contents2.size, Time.now)
    @tar << tar_file_contents(contents2)

    tgz = util_gzip(@tar)

    Zlib::GzipReader.wrap StringIO.new(tgz) do |gzio|
      util_entry(gzio).close # skip the first entry so io.pos is not 0
      entry = util_entry(gzio)

      entry.seek(50)
      assert_equal 50, entry.pos
      assert_equal contents2[50..-1], entry.read, "read remaining after seek"
      entry.seek(-50, IO::SEEK_CUR)
      assert_equal contents2.size - 50, entry.pos
      assert_equal contents2[-50..-1], entry.read, "read after stepping back 50 from the end"
      entry.seek(0, IO::SEEK_SET)
      assert_equal 0, entry.pos
      assert_equal contents2, entry.read, "read from beginning"
      entry.seek(-10, IO::SEEK_END)
      assert_equal contents2.size - 10, entry.pos
      assert_equal contents2[-10..-1], entry.read, "read from end"
      assert_equal contents2.size, entry.pos
    end
  end
end
