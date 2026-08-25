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
end
