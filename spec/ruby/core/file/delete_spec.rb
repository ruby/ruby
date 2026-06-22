require_relative '../../spec_helper'

describe "File.delete" do
  before :each do
    @file1 = tmp('test.txt')
    @file2 = tmp('test2.txt')

    touch @file1
    touch @file2
  end

  after :each do
    File.delete(@file1) if File.exist?(@file1)
    File.delete(@file2) if File.exist?(@file2)

    @file1 = nil
    @file2 = nil
  end

  it "returns 0 when called without arguments" do
    File.delete.should == 0
  end

  it "deletes a single file" do
    File.delete(@file1).should == 1
    File.should_not.exist?(@file1)
  end

  it "deletes multiple files" do
    File.delete(@file1, @file2).should == 2
    File.should_not.exist?(@file1)
    File.should_not.exist?(@file2)
  end

  it "raises a TypeError if not passed a String type" do
    -> { File.delete(1) }.should.raise(TypeError)
  end

  it "raises an Errno::ENOENT when the given file doesn't exist" do
    -> { File.delete('bogus') }.should.raise(Errno::ENOENT)
  end

  it "coerces a given parameter into a string if possible" do
    mock = mock("to_str")
    mock.should_receive(:to_str).and_return(@file1)
    File.delete(mock).should == 1
  end

  it "accepts an object that has a #to_path method" do
    File.delete(mock_to_path(@file1)).should == 1
  end

  platform_is :windows do
    it "allows deleting an open file with File::SHARE_DELETE" do
      path = tmp("share_delete.txt")
      File.open(path, mode: File::CREAT | File::WRONLY | File::BINARY | File::SHARE_DELETE) do |f|
        File.should.exist?(path)
        File.delete(path)
      end
      File.should_not.exist?(path)
    end
  end
end
