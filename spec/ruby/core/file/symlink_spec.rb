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
      -> { File.symlink(@file, @link) }.should raise_error(Errno::EEXIST)
    end

    it "raises an ArgumentError if not called with two arguments" do
      -> { File.symlink        }.should raise_error(ArgumentError)
      -> { File.symlink(@file) }.should raise_error(ArgumentError)
    end

    it "raises a TypeError if not called with String types" do
      -> { File.symlink(@file, nil) }.should raise_error(TypeError)
      -> { File.symlink(@file, 1)   }.should raise_error(TypeError)
      -> { File.symlink(1, 1)       }.should raise_error(TypeError)
    end
  end
end

describe "File.symlink?" do
  it_behaves_like :file_symlink, :symlink?, File
end

describe "File.symlink?" do
  it_behaves_like :file_symlink_nonexistent, :symlink?, File
end
