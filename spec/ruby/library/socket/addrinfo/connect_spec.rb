require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'Addrinfo#connect' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server = TCPServer.new(ip_address, 0)
      @port   = @server.connect_address.ip_port
    end

    after do
      @socket.close if @socket
      @server.close
    end

    it 'returns a Socket when no block is given' do
      addr = Addrinfo.tcp(ip_address, @port)
      @socket = addr.connect
      @socket.should be_an_instance_of(Socket)
    end

    it 'yields a Socket when a block is given' do
      addr = Addrinfo.tcp(ip_address, @port)
      addr.connect do |socket|
        socket.should be_an_instance_of(Socket)
      end
    end

    it 'accepts a Hash of options' do
      addr = Addrinfo.tcp(ip_address, @port)
      @socket = addr.connect(timeout: 2)
      @socket.should be_an_instance_of(Socket)
    end
  end
end
