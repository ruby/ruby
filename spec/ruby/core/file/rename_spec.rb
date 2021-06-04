require_relative '../../spec_helper'

describe "File.rename" do
  before :each do
    @old = tmp("file_rename.txt")
    @new = tmp("file_rename.new")

    rm_r @new
    touch(@old) { |f| f.puts "hello" }
  end

  after :each do
    rm_r @old, @new
  end

  it "renames a file" do
    File.should.exist?(@old)
    File.should_not.exist?(@new)
    File.rename(@old, @new)
    File.should_not.exist?(@old)
    File.should.exist?(@new)
  end

  it "raises an Errno::ENOENT if the source does not exist" do
    rm_r @old
    -> { File.rename(@old, @new) }.should raise_error(Errno::ENOENT)
  end

  it "raises an ArgumentError if not passed two arguments" do
    -> { File.rename        }.should raise_error(ArgumentError)
    -> { File.rename(@file) }.should raise_error(ArgumentError)
  end

  it "raises a TypeError if not passed String types" do
    -> { File.rename(1, 2)  }.should raise_error(TypeError)
  end
end
