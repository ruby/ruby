require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'Socket#accept' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server   = Socket.new(family, :STREAM, 0)
      @sockaddr = Socket.sockaddr_in(0, ip_address)
    end

    after do
      @server.close unless @server.closed?
    end

    platform_is :linux do # hangs on other platforms
      describe 'using an unbound socket'  do
        it 'raises Errno::EINVAL' do
          lambda { @server.accept }.should raise_error(Errno::EINVAL)
        end
      end

      describe "using a bound socket that's not listening" do
        before do
          @server.bind(@sockaddr)
        end

        it 'raises Errno::EINVAL' do
          lambda { @server.accept }.should raise_error(Errno::EINVAL)
        end
      end
    end

    describe 'using a closed socket' do
      it 'raises IOError' do
        @server.close

        lambda { @server.accept }.should raise_error(IOError)
      end
    end

    describe "using a bound socket that's listening" do
      before do
        @server.bind(@sockaddr)
        @server.listen(1)

        server_ip    = @server.local_address.ip_port
        @server_addr = Socket.sockaddr_in(server_ip, ip_address)
      end

      describe 'without a connected client' do
        it 'blocks the caller until a connection is available' do
          client = Socket.new(family, :STREAM, 0)
          thread = Thread.new do
            @server.accept
          end

          client.connect(@server_addr)

          thread.join(5)
          value = thread.value
          begin
            value.should be_an_instance_of(Array)
          ensure
            client.close
            value[0].close
          end
        end
      end

      describe 'with a connected client' do
        before do
          addr    = Socket.sockaddr_in(@server.local_address.ip_port, ip_address)
          @client = Socket.new(family, :STREAM, 0)

          @client.connect(addr)
        end

        after do
          @socket.close if @socket
          @client.close
        end

        it 'returns an Array containing a Socket and an Addrinfo' do
          @socket, addrinfo = @server.accept

          @socket.should be_an_instance_of(Socket)
          addrinfo.should be_an_instance_of(Addrinfo)
        end

        describe 'the returned Addrinfo' do
          before do
            @socket, @addr = @server.accept
          end

          it 'uses AF_INET as the address family' do
            @addr.afamily.should == family
          end

          it 'uses PF_INET as the protocol family' do
            @addr.pfamily.should == family
          end

          it 'uses SOCK_STREAM as the socket type' do
            @addr.socktype.should == Socket::SOCK_STREAM
          end

          it 'uses 0 as the protocol' do
            @addr.protocol.should == 0
          end

          it 'uses the same IP address as the client Socket' do
            @addr.ip_address.should == @client.local_address.ip_address
          end

          it 'uses the same port as the client Socket' do
            @addr.ip_port.should == @client.local_address.ip_port
          end
        end
      end
    end
  end
end
