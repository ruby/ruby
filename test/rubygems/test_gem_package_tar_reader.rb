# frozen_string_literal: true

require_relative "package/tar_test_case"
require "rubygems/package"

class TestGemPackageTarReader < Gem::Package::TarTestCase
  def test_each_entry
    tar = tar_dir_header "foo", "bar", 0, Time.now
    tar << tar_file_header("bar", "baz", 0, 0, Time.now)

    io = TempIO.new tar

    entries = 0

    Gem::Package::TarReader.new io do |tar_reader|
      tar_reader.each_entry do |entry|
        assert_kind_of Gem::Package::TarReader::Entry, entry

        entries += 1
      end
    end

    assert_equal 2, entries
  ensure
    io.close!
  end

  def test_rewind
    content = ("a".."z").to_a.join(" ")

    str =
      tar_file_header("lib/foo", "", 010644, content.size, Time.now) +
      content + "\0" * (512 - content.size)
    str << "\0" * 1024

    io = TempIO.new(str)

    Gem::Package::TarReader.new(io) do |tar_reader|
      3.times do
        tar_reader.rewind
        i = 0
        tar_reader.each_entry do |entry|
          assert_equal(content, entry.read)
          i += 1
        end
        assert_equal(1, i)
      end
    end
  ensure
    io.close!
  end

  def test_seek
    tar = tar_dir_header "foo", "bar", 0, Time.now
    tar << tar_file_header("bar", "baz", 0, 0, Time.now)

    io = TempIO.new tar

    Gem::Package::TarReader.new io do |tar_reader|
      retval = tar_reader.seek "baz/bar" do |entry|
        assert_kind_of Gem::Package::TarReader::Entry, entry

        assert_equal "baz/bar", entry.full_name
        entry.read
      end

      assert_equal "", retval
      assert_equal 0, io.pos
    end
  ensure
    io.close!
  end

  def test_seek_missing
    tar = tar_dir_header "foo", "bar", 0, Time.now
    tar << tar_file_header("bar", "baz", 0, 0, Time.now)

    io = TempIO.new tar

    Gem::Package::TarReader.new io do |tar_reader|
      tar_reader.seek "nonexistent" do |_entry|
        flunk "entry missing but entry-found block was run"
      end

      assert_equal 0, io.pos
    end
  ensure
    io.close!
  end

  def test_read_in_gem_data
    gem_tar = util_gem_data_tar do |tar|
      tar.add_file "lib/code.rb", 0444 do |io|
        io.write "# lib/code.rb"
      end
    end

    count = 0
    Gem::Package::TarReader.new(gem_tar).each do |entry|
      next unless entry.full_name == "data.tar.gz"

      Zlib::GzipReader.wrap entry do |gzio|
        Gem::Package::TarReader.new(gzio).each do |contents_entry|
          assert_equal "# lib/code.rb", contents_entry.read
          count += 1
        end
      end
    end

    assert_equal 1, count, "should have found one file"
  end

  def test_seek_in_gem_data
    gem_tar = util_gem_data_tar do |tar|
      tar.add_file "lib/code.rb", 0444 do |io|
        io.write "# lib/code.rb"
      end
      tar.add_file "lib/foo.rb", 0444 do |io|
        io.write "# lib/foo.rb"
      end
    end

    count = 0
    Gem::Package::TarReader.new(gem_tar).seek("data.tar.gz") do |entry|
      Zlib::GzipReader.wrap entry do |gzio|
        Gem::Package::TarReader.new(gzio).seek("lib/foo.rb") do |contents_entry|
          assert_equal "# lib/foo.rb", contents_entry.read
          count += 1
        end
      end
    end

    assert_equal 1, count, "should have found one file"
  end
end
