######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require "test/rubygems/gem_package_tar_test_case"
require 'rubygems/package'

class TestGemPackageTarReader < TarTestCase

  def test_each_entry
    tar = tar_dir_header "foo", "bar", 0
    tar << tar_file_header("bar", "baz", 0, 0)

    io = TempIO.new tar

    entries = 0

    Gem::Package::TarReader.new io do |tar_reader|
      tar_reader.each_entry do |entry|
        assert_kind_of Gem::Package::TarReader::Entry, entry

        entries += 1
      end
    end

    assert_equal 2, entries
  end

  def test_rewind
    content = ('a'..'z').to_a.join(" ")

    str = tar_file_header("lib/foo", "", 010644, content.size) + content +
            "\0" * (512 - content.size)
    str << "\0" * 1024

    Gem::Package::TarReader.new(TempIO.new(str)) do |tar_reader|
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
  end

end

