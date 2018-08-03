require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'Addrinfo#connect_to' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server = TCPServer.new(ip_address, 0)
      @port   = @server.connect_address.ip_port
      @addr   = Addrinfo.tcp(ip_address, 0)
    end

    after do
      @socket.close if @socket
      @server.close
    end

    describe 'using separate arguments' do
      it 'returns a Socket when no block is given' do
        @socket = @addr.connect_to(ip_address, @port)
        @socket.should be_an_instance_of(Socket)
      end

      it 'yields the Socket when a block is given' do
        @addr.connect_to(ip_address, @port) do |socket|
          socket.should be_an_instance_of(Socket)
        end
      end

      it 'treats the last argument as a set of options if it is a Hash' do
        @socket = @addr.connect_to(ip_address, @port, timeout: 2)
        @socket.should be_an_instance_of(Socket)
      end

      it 'binds the Addrinfo to the local address' do
        @socket = @addr.connect_to(ip_address, @port)

        @socket.local_address.ip_address.should == ip_address

        @socket.local_address.ip_port.should > 0
        @socket.local_address.ip_port.should_not == @port
      end
    end

    describe 'using an Addrinfo as the 1st argument' do
      before do
        @to_addr = Addrinfo.tcp(ip_address, @port)
      end

      it 'returns a Socket when no block is given' do
        @socket = @addr.connect_to(@to_addr)
        @socket.should be_an_instance_of(Socket)
      end

      it 'yields the Socket when a block is given' do
        @addr.connect_to(@to_addr) do |socket|
          socket.should be_an_instance_of(Socket)
        end
      end

      it 'treats the last argument as a set of options if it is a Hash' do
        @socket = @addr.connect_to(@to_addr, timeout: 2)
        @socket.should be_an_instance_of(Socket)
      end

      it 'binds the socket to the local address' do
        @socket = @addr.connect_to(@to_addr)

        @socket.local_address.ip_address.should == ip_address

        @socket.local_address.ip_port.should > 0
        @socket.local_address.ip_port.should_not == @port
      end
    end
  end
end
