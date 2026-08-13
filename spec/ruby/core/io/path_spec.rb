require_relative '../../spec_helper'

describe "IO#path" do
  it "returns the path of the file associated with the IO object" do
    path = tmp("io_path.txt")
    File.open(path, "w") do |file|
      IO.new(file.fileno, path: file.path, autoclose: false).path.should == file.path
    end
  ensure
    File.unlink(path)
  end

  it "is set for STDIN" do
    STDIN.path.should == "<STDIN>"
  end

  it "is set for STDOUT" do
    STDOUT.path.should == "<STDOUT>"
  end

  it "is set for STDERR" do
    STDERR.path.should == "<STDERR>"
  end
end
