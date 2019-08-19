require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'Socket#remote_address' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server = Socket.new(family, :STREAM)

      @server.bind(Socket.sockaddr_in(0, ip_address))
      @server.listen(1)

      @host   = @server.local_address.ip_address
      @port   = @server.local_address.ip_port
      @client = Socket.new(family, :STREAM, Socket::IPPROTO_TCP)

      @client.connect(Socket.sockaddr_in(@port, @host))
    end

    after do
      @client.close
      @server.close
    end

    it 'returns an Addrinfo' do
      @client.remote_address.should be_an_instance_of(Addrinfo)
    end

    describe 'the returned Addrinfo' do
      it 'uses AF_INET as the address family' do
        @client.remote_address.afamily.should == family
      end

      it 'uses PF_INET as the protocol family' do
        @client.remote_address.pfamily.should == family
      end

      it 'uses SOCK_STREAM as the socket type' do
        @client.remote_address.socktype.should == Socket::SOCK_STREAM
      end

      it 'uses the correct IP address' do
        @client.remote_address.ip_address.should == @host
      end

      it 'uses the correct port' do
        @client.remote_address.ip_port.should == @port
      end

      it 'uses 0 as the protocol' do
        @client.remote_address.protocol.should == 0
      end
    end
  end
end
