require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket::BasicSocket#close_write" do
  before :each do
    @server = TCPServer.new(0)
  end

  after :each do
    @server.close unless @server.closed?
  end

  it "closes the writing end of the socket" do
    @server.close_write
    -> { @server.write("foo") }.should.raise(IOError)
  end

  ruby_version_is "4.1" do
    platform_is_not :windows do
      it "flushes buffered data to the peer before shutting down the write side" do
        UNIXSocket.pair do |s1, s2|
          s1.sync = false
          s1.write("buffered")
          s1.close_write
          s2.read.should == "buffered"
        end
      end
    end
  end

  it 'does not raise when called on a socket already closed for writing' do
    @server.close_write
    @server.close_write
    -> { @server.write("foo") }.should.raise(IOError)
  end

  it 'does not fully close the socket' do
    @server.close_write
    @server.closed?.should == false
  end

  it "does not prevent reading" do
    @server.close_write
    @server.read(0).should == ""
  end

  it "fully closes the socket if it was already closed for reading" do
    @server.close_read
    @server.close_write
    @server.closed?.should == true
  end

  it 'raises IOError when called on a fully closed socket' do
    @server.close
    -> { @server.close_write }.should.raise(IOError)
  end

  it "returns nil" do
    @server.close_write.should == nil
  end
end
