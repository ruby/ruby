require_relative '../../spec_helper'
require_relative '../../shared/file/symlink'

describe "File.symlink" do
  before :each do
    @file = tmp("file_symlink.txt")
    @link = tmp("file_symlink.lnk")

    rm_r @link
    touch @file
  end

  after :each do
    rm_r @link, @file
  end

  platform_is_not :windows do
    it "creates a symlink between a source and target file" do
      File.symlink(@file, @link).should == 0
      File.identical?(@file, @link).should == true
    end

    it "creates a symbolic link" do
      File.symlink(@file, @link)
      File.symlink?(@link).should == true
    end

    it "accepts args that have #to_path methods" do
      File.symlink(mock_to_path(@file), mock_to_path(@link))
      File.symlink?(@link).should == true
    end

    it "raises an Errno::EEXIST if the target already exists" do
      File.symlink(@file, @link)
      -> { File.symlink(@file, @link) }.should.raise(Errno::EEXIST)
    end

    it "raises an ArgumentError if not called with two arguments" do
      -> { File.symlink        }.should.raise(ArgumentError)
      -> { File.symlink(@file) }.should.raise(ArgumentError)
    end

    it "raises a TypeError if not called with String types" do
      -> { File.symlink(@file, nil) }.should.raise(TypeError)
      -> { File.symlink(@file, 1)   }.should.raise(TypeError)
      -> { File.symlink(1, 1)       }.should.raise(TypeError)
    end

    platform_is :darwin do
      it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
        utf8_file = tmp("file_symlink_file_utf8_path_\u{3042}.txt")
        utf8_link = tmp("file_symlink_link_utf8_path_\u{3042}.txt")
        # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
        non_utf8_file = utf8_file.encode(Encoding::Windows_31J)
        non_utf8_link = utf8_link.encode(Encoding::Windows_31J)

        begin
          touch(utf8_file)
          File.symlink(non_utf8_file, non_utf8_link).should == 0
        ensure
          rm_r utf8_file, utf8_link
          rm_r non_utf8_file, non_utf8_link
        end
      end
    end
  end
end

describe "File.symlink?" do
  it_behaves_like :file_symlink, :symlink?, File
end

describe "File.symlink?" do
  it_behaves_like :file_symlink_nonexistent, :symlink?, File
end
