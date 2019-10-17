require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'UDPSocket#connect' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @socket = UDPSocket.new(family)
    end

    after do
      @socket.close
    end

    it 'connects to an address even when it is not used' do
      @socket.connect(ip_address, 9996).should == 0
    end

    it 'can send data after connecting' do
      receiver = UDPSocket.new(family)

      receiver.bind(ip_address, 0)

      addr = receiver.connect_address

      @socket.connect(addr.ip_address, addr.ip_port)
      @socket.write('hello')

      begin
        receiver.recv(6).should == 'hello'
      ensure
        receiver.close
      end
    end
  end
end
