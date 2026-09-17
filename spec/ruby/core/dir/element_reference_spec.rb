require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/glob'

describe "Dir.[]" do
  it_behaves_like :dir_glob, :[]
end

describe "Dir.[]" do
  it_behaves_like :dir_glob_recursive, :[]
end

describe "Dir.[]" do
  before :all do
    DirSpecs.create_mock_dirs
    @cwd = Dir.pwd
    Dir.chdir DirSpecs.mock_dir
  end

  after :all do
    Dir.chdir @cwd
    DirSpecs.delete_mock_dirs
  end

  it "calls #to_path to convert multiple patterns" do
    pat1 = mock('file_one.ext')
    pat1.should_receive(:to_path).and_return('file_one.ext')
    pat2 = mock('file_two.ext')
    pat2.should_receive(:to_path).and_return('file_two.ext')

    Dir[pat1, pat2].should == %w[file_one.ext file_two.ext]
  end

  it "preserves the encoding of the path" do
    pattern1 = "file_one.ext".encode(Encoding::EUC_JP)
    pattern2 = "file_two.ext".encode(Encoding::EUC_JP)
    results = Dir[pattern1, pattern2]
    results.map(&:encoding).should == [Encoding::EUC_JP, Encoding::EUC_JP]
  end

  platform_is :darwin do
    it "accepts multiple patterns in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      dir = tmp("dir_glob_\u{3042}")
      utf8_file = File.join(dir, "file.txt")
      non_utf8_pattern = File.join(dir, "*.txt").encode(Encoding::Windows_31J)

      begin
        mkdir_p(dir)
        touch(utf8_file)
        Dir[non_utf8_pattern, non_utf8_pattern].should == [
          utf8_file.encode(Encoding::Windows_31J),
          utf8_file.encode(Encoding::Windows_31J)
        ]
      ensure
        rm_r dir
      end
    end
  end
end
