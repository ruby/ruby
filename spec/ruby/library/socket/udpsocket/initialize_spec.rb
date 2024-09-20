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

  platform_is_not :windows do
    it 'sets the socket to nonblock' do
      require 'io/nonblock'
      @socket = UDPSocket.new(:INET)
      @socket.should.nonblock?
    end
  end

  it 'sets the socket to close on exec' do
    @socket = UDPSocket.new(:INET)
    @socket.should.close_on_exec?
  end

  it 'raises Errno::EAFNOSUPPORT or Errno::EPROTONOSUPPORT when given an invalid address family' do
    -> {
      UDPSocket.new(666)
    }.should raise_error(SystemCallError) { |e|
      [Errno::EAFNOSUPPORT, Errno::EPROTONOSUPPORT].should include(e.class)
    }
  end
end
