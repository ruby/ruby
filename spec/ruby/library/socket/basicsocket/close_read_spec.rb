require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket::BasicSocket#close_read" do
  before :each do
    @server = TCPServer.new(0)
  end

  after :each do
    @server.close unless @server.closed?
  end

  it "closes the reading end of the socket" do
    @server.close_read
    -> { @server.read }.should raise_error(IOError)
  end

  it 'does not raise when called on a socket already closed for reading' do
    @server.close_read
    @server.close_read
    -> { @server.read }.should raise_error(IOError)
  end

  it 'does not fully close the socket' do
    @server.close_read
    @server.closed?.should be_false
  end

  it "fully closes the socket if it was already closed for writing" do
    @server.close_write
    @server.close_read
    @server.closed?.should be_true
  end

  it 'raises IOError when called on a fully closed socket' do
    @server.close
    -> { @server.close_read }.should raise_error(IOError)
  end

  it "returns nil" do
    @server.close_read.should be_nil
  end
end
