require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'Socket#connect_address' do
  describe 'using an unbound socket' do
    after do
      @sock.close
    end

    it 'raises SocketError' do
      @sock = Socket.new(:INET, :STREAM)

      -> { @sock.connect_address }.should raise_error(SocketError)
    end
  end

  describe 'using a socket bound to 0.0.0.0' do
    before do
      @sock = Socket.new(:INET, :STREAM)
      @sock.bind(Socket.sockaddr_in(0, '0.0.0.0'))
    end

    after do
      @sock.close
    end

    it 'returns an Addrinfo' do
      @sock.connect_address.should be_an_instance_of(Addrinfo)
    end

    it 'uses 127.0.0.1 as the IP address' do
      @sock.connect_address.ip_address.should == '127.0.0.1'
    end

    it 'uses the correct port number' do
      @sock.connect_address.ip_port.should > 0
    end

    it 'uses AF_INET as the address family' do
      @sock.connect_address.afamily.should == Socket::AF_INET
    end

    it 'uses PF_INET as the address family' do
      @sock.connect_address.pfamily.should == Socket::PF_INET
    end

    it 'uses SOCK_STREAM as the socket type' do
      @sock.connect_address.socktype.should == Socket::SOCK_STREAM
    end

    it 'uses 0 as the protocol' do
      @sock.connect_address.protocol.should == 0
    end
  end

  guard -> { SocketSpecs.ipv6_available? } do
    describe 'using a socket bound to ::' do
      before do
        @sock = Socket.new(:INET6, :STREAM)
        @sock.bind(Socket.sockaddr_in(0, '::'))
      end

      after do
        @sock.close
      end

      it 'returns an Addrinfo' do
        @sock.connect_address.should be_an_instance_of(Addrinfo)
      end

      it 'uses ::1 as the IP address' do
        @sock.connect_address.ip_address.should == '::1'
      end

      it 'uses the correct port number' do
        @sock.connect_address.ip_port.should > 0
      end

      it 'uses AF_INET6 as the address family' do
        @sock.connect_address.afamily.should == Socket::AF_INET6
      end

      it 'uses PF_INET6 as the address family' do
        @sock.connect_address.pfamily.should == Socket::PF_INET6
      end

      it 'uses SOCK_STREAM as the socket type' do
        @sock.connect_address.socktype.should == Socket::SOCK_STREAM
      end

      it 'uses 0 as the protocol' do
        @sock.connect_address.protocol.should == 0
      end
    end
  end

  with_feature :unix_socket do
    platform_is_not :aix do
      describe 'using an unbound UNIX socket' do
        before do
          @path = SocketSpecs.socket_path
          @server = UNIXServer.new(@path)
          @client = UNIXSocket.new(@path)
        end

        after do
          @client.close
          @server.close
          rm_r(@path)
        end

        it 'raises SocketError' do
          -> { @client.connect_address }.should raise_error(SocketError)
        end
      end
    end

    describe 'using a bound UNIX socket' do
      before do
        @path = SocketSpecs.socket_path
        @sock = UNIXServer.new(@path)
      end

      after do
        @sock.close
        rm_r(@path)
      end

      it 'returns an Addrinfo' do
        @sock.connect_address.should be_an_instance_of(Addrinfo)
      end

      it 'uses the correct socket path' do
        @sock.connect_address.unix_path.should == @path
      end

      it 'uses AF_UNIX as the address family' do
        @sock.connect_address.afamily.should == Socket::AF_UNIX
      end

      it 'uses PF_UNIX as the protocol family' do
        @sock.connect_address.pfamily.should == Socket::PF_UNIX
      end

      it 'uses SOCK_STREAM as the socket type' do
        @sock.connect_address.socktype.should == Socket::SOCK_STREAM
      end

      it 'uses 0 as the protocol' do
        @sock.connect_address.protocol.should == 0
      end
    end
  end
end
