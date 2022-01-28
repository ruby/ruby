require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/closed'

describe "Dir#read" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  it "returns the file name in the current seek position" do
    # an FS does not necessarily impose order
    ls = Dir.entries DirSpecs.mock_dir
    dir = Dir.open DirSpecs.mock_dir
    ls.should include(dir.read)
    dir.close
  end

  it "returns nil when there are no more entries" do
    dir = Dir.open DirSpecs.mock_dir
    DirSpecs.expected_paths.size.times do
      dir.read.should_not == nil
    end
    dir.read.should == nil
    dir.close
  end

  it "returns each entry successively" do
    dir = Dir.open DirSpecs.mock_dir
    entries = []
    while entry = dir.read
      entries << entry
    end
    dir.close

    entries.sort.should == DirSpecs.expected_paths
  end

  platform_is_not :windows do
    it "returns all directory entries even when encoding conversion will fail" do
      dir = Dir.open(File.join(DirSpecs.mock_dir, 'special'))
      utf8_entries = []
      begin
        while entry = dir.read
          utf8_entries << entry
        end
      ensure
        dir.close
      end
      old_internal_encoding = Encoding::default_internal
      old_external_encoding = Encoding::default_external
      Encoding.default_internal = Encoding::UTF_8
      Encoding.default_external = Encoding::SHIFT_JIS
      dir = Dir.open(File.join(DirSpecs.mock_dir, 'special'))
      shift_jis_entries = []
      begin
        -> {
          while entry = dir.read
            shift_jis_entries << entry
          end
        }.should_not raise_error
      ensure
        dir.close
        Encoding.default_internal = old_internal_encoding
        Encoding.default_external = old_external_encoding
      end
      shift_jis_entries.size.should == utf8_entries.size
      shift_jis_entries.filter { |f| f.encoding == Encoding::SHIFT_JIS }.size.should == 1
    end
  end

  it_behaves_like :dir_closed, :read
end
