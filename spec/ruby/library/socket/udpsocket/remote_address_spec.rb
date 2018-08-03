require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'UDPSocket#remote_address' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server = Socket.new(family, :DGRAM, Socket::IPPROTO_UDP)

      @server.bind(Socket.sockaddr_in(0, ip_address))

      @host = @server.connect_address.ip_address
      @port = @server.connect_address.ip_port
    end

    after do
      @server.close
    end

    describe 'using an explicit hostname' do
      before do
        @sock = UDPSocket.new(family)

        @sock.connect(@host, @port)
      end

      after do
        @sock.close
      end

      it 'returns an Addrinfo' do
        @sock.remote_address.should be_an_instance_of(Addrinfo)
      end

      describe 'the returned Addrinfo' do
        it 'uses the correct address family' do
          @sock.remote_address.afamily.should == family
        end

        it 'uses the correct protocol family' do
          @sock.remote_address.pfamily.should == family
        end

        it 'uses SOCK_DGRAM as the socket type' do
          @sock.remote_address.socktype.should == Socket::SOCK_DGRAM
        end

        it 'uses the correct IP address' do
          @sock.remote_address.ip_address.should == @host
        end

        it 'uses the correct port' do
          @sock.remote_address.ip_port.should == @port
        end

        it 'uses 0 as the protocol' do
          @sock.remote_address.protocol.should == 0
        end
      end
    end

    describe 'using an implicit hostname' do
      before do
        @sock = UDPSocket.new(family)

        @sock.connect(nil, @port)
      end

      after do
        @sock.close
      end

      describe 'the returned Addrinfo' do
        it 'uses the correct IP address' do
          @sock.remote_address.ip_address.should == @host
        end
      end
    end
  end
end
