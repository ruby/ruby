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
    lambda { @server.write("foo") }.should raise_error(IOError)
  end

  it 'does not raise when called on a socket already closed for writing' do
    @server.close_write
    @server.close_write
    lambda { @server.write("foo") }.should raise_error(IOError)
  end

  it 'does not fully close the socket' do
    @server.close_write
    @server.closed?.should be_false
  end

  it "does not prevent reading" do
    @server.close_write
    @server.read(0).should == ""
  end

  it "fully closes the socket if it was already closed for reading" do
    @server.close_read
    @server.close_write
    @server.closed?.should be_true
  end

  it 'raises IOError when called on a fully closed socket' do
    @server.close
    lambda { @server.close_write }.should raise_error(IOError)
  end

  it "returns nil" do
    @server.close_write.should be_nil
  end
end
