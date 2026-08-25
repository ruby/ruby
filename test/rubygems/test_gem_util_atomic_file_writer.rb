# frozen_string_literal: true

require_relative "helper"
require "rubygems/util/atomic_file_writer"

class TestGemUtilAtomicFileWriter < Gem::TestCase
  def setup
    super

    @dir = File.join @tempdir, "atomic"
    Dir.mkdir @dir
    @path = File.join @dir, "out.txt"
  end

  def test_external_encoding
    Gem::AtomicFileWriter.open(@path) do |file|
      assert_equal(Encoding::ASCII_8BIT, file.external_encoding)
    end
  end

  def test_returns_block_value_and_leaves_no_temp_file
    result = Gem::AtomicFileWriter.open(@path) do |file|
      file.write "hello"
      :done
    end

    assert_equal :done, result
    assert_equal "hello", File.binread(@path)
    assert_equal ["out.txt"], Dir.children(@dir)
  end

  def test_content_is_flushed_before_rename
    original_rename = File.method(:rename)
    size_at_rename = nil

    rename_spy = lambda do |src, dest|
      size_at_rename = File.size(src)
      original_rename.call(src, dest)
    end

    File.stub(:rename, rename_spy) do
      Gem::AtomicFileWriter.open(@path) do |file|
        file.write "hello"
      end
    end

    assert_equal 5, size_at_rename
    assert_equal "hello", File.binread(@path)
  end

  def test_keeps_destination_and_removes_temp_file_on_error
    File.binwrite @path, "old"

    error = assert_raise(RuntimeError) do
      Gem::AtomicFileWriter.open(@path) do |file|
        file.write "new"
        raise "boom"
      end
    end

    assert_equal "boom", error.message
    assert_equal "old", File.binread(@path)
    assert_equal ["out.txt"], Dir.children(@dir)
  end

  def test_keeps_destination_and_removes_temp_file_on_interrupt
    File.binwrite @path, "old"

    assert_raise(Interrupt) do
      Gem::AtomicFileWriter.open(@path) do |file|
        file.write "new"
        raise Interrupt
      end
    end

    assert_equal "old", File.binread(@path)
    assert_equal ["out.txt"], Dir.children(@dir)
  end

  def test_removes_temp_file_when_closing_it_keeps_raising
    File.binwrite @path, "old"

    temp_file = nil
    closes = 0
    raising = true
    # A real file is closed even when its close raises, so only a stub can keep
    # raising like this. The writer leaves that file to the garbage collector,
    # which is why this test closes it itself.
    failing_open = temp_file_open_stub do |file|
      temp_file = file
      file.define_singleton_method(:close) do
        closes += 1
        raise Interrupt if raising

        super()
      end
    end

    File.stub(:open, failing_open) do
      assert_raise(Interrupt) do
        Gem::AtomicFileWriter.open(@path) do |file|
          file.write "new"
        end
      end
    end

    assert_equal 2, closes
    assert_equal "old", File.binread(@path)
    assert_equal ["out.txt"], Dir.children(@dir)
  ensure
    raising = false
    temp_file&.close
  end

  def test_keeps_destination_when_closing_the_temp_file_fails
    File.binwrite @path, "old"

    failing_open = temp_file_open_stub do |file|
      file.define_singleton_method(:close) do
        super()
        raise Errno::ENOSPC
      end
    end

    File.stub(:open, failing_open) do
      assert_raise(Errno::ENOSPC) do
        Gem::AtomicFileWriter.open(@path) do |file|
          file.write "new"
        end
      end
    end

    assert_equal "old", File.binread(@path)
    assert_equal ["out.txt"], Dir.children(@dir)
  end

  def test_keeps_destination_when_renaming_fails
    File.binwrite @path, "old"

    File.stub(:rename, ->(_src, _dest) { raise Errno::EXDEV }) do
      assert_raise(Errno::EXDEV) do
        Gem::AtomicFileWriter.open(@path) do |file|
          file.write "new"
        end
      end
    end

    assert_equal "old", File.binread(@path)
    assert_equal ["out.txt"], Dir.children(@dir)
  end

  def test_preserves_destination_permissions
    pend "Windows cannot round-trip the POSIX permission bits" if Gem.win_platform?

    File.binwrite @path, "old"
    File.chmod 0o604, @path

    Gem::AtomicFileWriter.open(@path) do |file|
      file.write "new"
    end

    assert_equal "new", File.binread(@path)
    assert_equal 0o604, File.stat(@path).mode & 0o777
  end

  def test_multibyte_basename_is_truncated_at_char_boundary
    pend "long file names easily exceed MAX_PATH on Windows" if Gem.win_platform?

    path = File.join @dir, "#{"あ" * 82}.txt"
    original_rename = File.method(:rename)
    tmp_basename = nil

    rename_spy = lambda do |src, dest|
      tmp_basename ||= File.basename(src)
      original_rename.call(src, dest)
    end

    # Filesystems that store names as raw bytes, such as ext4, happily create a
    # temporary file whose name is cut in the middle of a character, so assert on
    # the name itself rather than on the destination write failing.
    File.stub(:rename, rename_spy) do
      Gem::AtomicFileWriter.open(path) do |file|
        file.write "hello"
      end
    end

    assert_predicate tmp_basename, :valid_encoding?
    assert_operator tmp_basename.bytesize, :<=, 255
    assert_equal "hello", File.binread(path)
    assert_equal 1, Dir.children(@dir).size
  end

  def test_long_basename_is_truncated_to_the_name_length_limit
    pend "long file names easily exceed MAX_PATH on Windows" if Gem.win_platform?

    path = File.join @dir, "#{"a" * 250}.txt"
    original_rename = File.method(:rename)
    tmp_basename = nil

    rename_spy = lambda do |src, dest|
      tmp_basename ||= File.basename(src)
      original_rename.call(src, dest)
    end

    File.stub(:rename, rename_spy) do
      Gem::AtomicFileWriter.open(path) do |file|
        file.write "hello"
      end
    end

    assert_equal 255, tmp_basename.bytesize
    assert_equal "hello", File.binread(path)
  end

  def test_byteslice_at_char_boundary
    sliced = Gem::AtomicFileWriter.send :byteslice_at_char_boundary, "あいう", 4

    assert_equal "あ", sliced
    assert_predicate sliced, :valid_encoding?
  end

  def test_byteslice_at_char_boundary_with_invalid_encoding
    invalid = "\xFFabc".dup.force_encoding(Encoding::UTF_8)
    refute_predicate invalid, :valid_encoding?

    sliced = Gem::AtomicFileWriter.send :byteslice_at_char_boundary, invalid, 2

    assert_equal "\xFFa".dup.force_encoding(Encoding::UTF_8), sliced
  end

  private

  # Returns a File.open replacement that hands the writer's temporary file to
  # the given block, which installs whatever close behaviour a test needs.
  # Every other path is opened normally. Call this before installing the stub,
  # since it captures the current File.open.
  def temp_file_open_stub(&injection)
    original_open = File.method(:open)
    prefix = ".#{File.basename(@path)}.tmp."

    lambda do |name, *args, **kwargs, &block|
      unless File.basename(name.to_s).start_with?(prefix)
        next original_open.call(name, *args, **kwargs, &block)
      end
      raise ArgumentError, "this stub cannot replace close on a File.open with a block" if block

      file = original_open.call(name, *args, **kwargs)
      begin
        injection.call(file)
      rescue StandardError
        file.close
        raise
      end
      file
    end
  end
end
