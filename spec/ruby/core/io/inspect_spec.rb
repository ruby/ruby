require_relative '../../spec_helper'

describe "IO#inspect" do
  before :each do
    @path = tmp("foo")
  end

  after :each do
    File.delete(@path) if File.exist?(@path)
  end

  it "contains the file descriptor number if no path is given" do
    fd = new_fd(@path)
    io = IO.open(fd)
    io.inspect.should == "#<IO:fd #{fd}>"

    io.close
    io.inspect.should == "#<IO:(closed)>"
  ensure
    io&.close
  end

  it "contains the path if a path is given" do
    fd = new_fd(@path)
    io = IO.open(fd, path: @path)
    io.inspect.should == "#<IO:#{@path}>"

    io.close
    io.inspect.should == "#<IO:#{@path} (closed)>"
  ensure
    io&.close
  end

  it "contains the subclass in its result" do
    File.open(@path, "w") do |file|
      file.inspect.should == "#<File:#{@path}>"
    end
  end

  it "reports IO as its Method object's owner" do
    IO.instance_method(:inspect).owner.should == IO
  end
end
