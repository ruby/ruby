require File.expand_path('../../../../spec_helper', __FILE__)
require File.expand_path('../../fixtures/classes', __FILE__)

describe "Socket::BasicSocket#getsockname" do
  after :each do
    @socket.closed?.should be_false
    @socket.close
  end

  it "returns the sockaddr associacted with the socket" do
    @socket = TCPServer.new("127.0.0.1", SocketSpecs.port)
    sockaddr = Socket.unpack_sockaddr_in(@socket.getsockname)
    sockaddr.should == [SocketSpecs.port, "127.0.0.1"]
 end

  it "works on sockets listening in ipaddr_any" do
    @socket = TCPServer.new(SocketSpecs.port)
    sockaddr = Socket.unpack_sockaddr_in(@socket.getsockname)
    ["::", "0.0.0.0", "::ffff:0.0.0.0"].include?(sockaddr[1]).should be_true
    sockaddr[0].should == SocketSpecs.port
  end

  it "returns empty sockaddr for unbinded sockets" do
    @socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    sockaddr = Socket.unpack_sockaddr_in(@socket.getsockname)
    sockaddr.should == [0, "0.0.0.0"]
  end
end
