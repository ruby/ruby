require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#close_read" do

  before :each do
    @io = IO.popen 'cat', "r+"
    @path = tmp('io.close.txt')
  end

  after :each do
    @io.close unless @io.closed?
    rm_r @path
  end

  it "closes the read end of a duplex I/O stream" do
    @io.close_read

    lambda { @io.read }.should raise_error(IOError)
  end

  it "does nothing on subsequent invocations" do
    @io.close_read

    @io.close_read.should be_nil
  end

  it "allows subsequent invocation of close" do
    @io.close_read

    lambda { @io.close }.should_not raise_error
  end

  it "raises an IOError if the stream is writable and not duplexed" do
    io = File.open @path, 'w'

    begin
      lambda { io.close_read }.should raise_error(IOError)
    ensure
      io.close unless io.closed?
    end
  end

  it "closes the stream if it is neither writable nor duplexed" do
    io_close_path = @path
    touch io_close_path

    io = File.open io_close_path

    io.close_read

    io.closed?.should == true
  end

  it "does nothing on closed stream" do
    @io.close

    @io.close_read.should be_nil
  end
end
