require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'UDPSocket.new' do
  after :each do
    @socket.close if @socket && !@socket.closed?
  end

  it 'without arguments' do
    @socket = UDPSocket.new
    @socket.should be_an_instance_of(UDPSocket)
  end

  it 'using Integer argument' do
    @socket = UDPSocket.new(Socket::AF_INET)
    @socket.should be_an_instance_of(UDPSocket)
  end

  it 'using Symbol argument' do
    @socket = UDPSocket.new(:INET)
    @socket.should be_an_instance_of(UDPSocket)
  end

  it 'using String argument' do
    @socket = UDPSocket.new('INET')
    @socket.should be_an_instance_of(UDPSocket)
  end

  it 'raises Errno::EAFNOSUPPORT or Errno::EPROTONOSUPPORT if unsupported family passed' do
    lambda { UDPSocket.new(-1) }.should raise_error(SystemCallError) { |e|
      [Errno::EAFNOSUPPORT, Errno::EPROTONOSUPPORT].should include(e.class)
    }
  end
end
