require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket::BasicSocket#getpeername" do

  before :each do
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @client = TCPSocket.new("127.0.0.1", @port)
  end

  after :each do
    @server.close unless @server.closed?
    @client.close unless @client.closed?
  end

  it "returns the sockaddr of the other end of the connection" do
    server_sockaddr = Socket.pack_sockaddr_in(@port, "127.0.0.1")
    @client.getpeername.should == server_sockaddr
  end

  it 'raises Errno::ENOTCONN for a disconnected socket' do
    lambda { @server.getpeername }.should raise_error(Errno::ENOTCONN)
  end
end
