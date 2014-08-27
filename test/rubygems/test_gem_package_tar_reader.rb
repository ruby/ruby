require 'rubygems/package/tar_test_case'
require 'rubygems/package'

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
    content = ('a'..'z').to_a.join(" ")

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
      tar_reader.seek 'baz/bar' do |entry|
        assert_kind_of Gem::Package::TarReader::Entry, entry

        assert_equal 'baz/bar', entry.full_name
      end

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
      tar_reader.seek 'nonexistent' do |entry|
        flunk 'entry missing but entry-found block was run'
      end

      assert_equal 0, io.pos
    end
  ensure
    io.close!
  end

end

