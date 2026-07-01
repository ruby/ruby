require_relative '../spec_helper'

describe 'IPSocket#inspect' do
  it "returns a String with the fd, family, address and port for TCPSocket" do
    @server = TCPServer.new("127.0.0.1", 0)
    @socket = TCPSocket.new("127.0.0.1", @server.addr[1])
    port = @socket.addr[1]

    @socket.inspect.should == "#<TCPSocket:fd #{@socket.fileno}, AF_INET, 127.0.0.1, #{port}>"
  ensure
    @socket&.close
    @server&.close
  end

  it 'returns a String with the fd, family, address and port for UDPSocket' do
    @socket = UDPSocket.new
    @socket.bind('127.0.0.1', 0)
    port = @socket.addr[1]

    @socket.inspect.should == "#<UDPSocket:fd #{@socket.fileno}, AF_INET, 127.0.0.1, #{port}>"
  ensure
    @socket&.close
  end
end
