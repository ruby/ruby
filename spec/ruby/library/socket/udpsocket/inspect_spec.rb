require_relative '../spec_helper'

describe 'UDPSocket#inspect' do
  before do
    @socket = UDPSocket.new
    @socket.bind('127.0.0.1', 0)
  end

  after do
    @socket.close
  end

  it 'returns a String with the fd, family, address and port' do
    port = @socket.addr[1]
    @socket.inspect.should == "#<UDPSocket:fd #{@socket.fileno}, AF_INET, 127.0.0.1, #{port}>"
  end
end
