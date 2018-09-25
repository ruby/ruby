require_relative '../spec_helper'

describe 'UDPSocket#initialize' do
  after do
    @socket.close if @socket
  end

  it 'initializes a new UDPSocket' do
    @socket = UDPSocket.new
    @socket.should be_an_instance_of(UDPSocket)
  end

  it 'initializes a new UDPSocket using an Integer' do
    @socket = UDPSocket.new(Socket::AF_INET)
    @socket.should be_an_instance_of(UDPSocket)
  end

  it 'initializes a new UDPSocket using a Symbol' do
    @socket = UDPSocket.new(:INET)
    @socket.should be_an_instance_of(UDPSocket)
  end

  it 'initializes a new UDPSocket using a String' do
    @socket = UDPSocket.new('INET')
    @socket.should be_an_instance_of(UDPSocket)
  end

  it 'sets the socket to binmode' do
    @socket = UDPSocket.new(:INET)
    @socket.binmode?.should be_true
  end

  it 'raises Errno::EAFNOSUPPORT when given an invalid address family' do
    lambda { UDPSocket.new(666) }.should raise_error(Errno::EAFNOSUPPORT)
  end
end
