require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#initialize" do
  before :each do
    @name = tmp("io_initialize.txt")
    @io = new_io @name
    @fd = @io.fileno
  end

  after :each do
    @io.close if @io
    rm_r @name
  end

  it "reassociates the IO instance with the new descriptor when passed a Fixnum" do
    fd = new_fd @name, "r:utf-8"
    @io.send :initialize, fd, 'r'
    @io.fileno.should == fd
  end

  it "calls #to_int to coerce the object passed as an fd" do
    obj = mock('fileno')
    fd = new_fd @name, "r:utf-8"
    obj.should_receive(:to_int).and_return(fd)
    @io.send :initialize, obj, 'r'
    @io.fileno.should == fd
  end

  it "raises a TypeError when passed an IO" do
    -> { @io.send :initialize, STDOUT, 'w' }.should raise_error(TypeError)
  end

  it "raises a TypeError when passed nil" do
    -> { @io.send :initialize, nil, 'w' }.should raise_error(TypeError)
  end

  it "raises a TypeError when passed a String" do
    -> { @io.send :initialize, "4", 'w' }.should raise_error(TypeError)
  end

  it "raises IOError on closed stream" do
    -> { @io.send :initialize, IOSpecs.closed_io.fileno }.should raise_error(IOError)
  end

  it "raises an Errno::EBADF when given an invalid file descriptor" do
    -> { @io.send :initialize, -1, 'w' }.should raise_error(Errno::EBADF)
  end
end
