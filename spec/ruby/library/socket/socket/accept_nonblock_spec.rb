require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket#accept_nonblock" do
  before :each do
    @hostname = "127.0.0.1"
    @addr = Socket.sockaddr_in(0, @hostname)
    @socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    @socket.bind(@addr)
    @socket.listen(1)
  end

  after :each do
    @socket.close
  end

  it "raises IO::WaitReadable if the connection is not accepted yet" do
    -> {
      @socket.accept_nonblock
    }.should raise_error(IO::WaitReadable) { |e|
      platform_is_not :windows do
        e.should be_kind_of(Errno::EAGAIN)
      end
      platform_is :windows do
        e.should be_kind_of(Errno::EWOULDBLOCK)
      end
    }
  end

  it 'returns :wait_readable in exceptionless mode' do
    @socket.accept_nonblock(exception: false).should == :wait_readable
  end
end

describe 'Socket#accept_nonblock' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server = Socket.new(family, :STREAM, 0)
      @sockaddr = Socket.sockaddr_in(0, ip_address)
    end

    after do
      @server.close unless @server.closed?
    end

    describe 'using an unbound socket' do
      it 'raises Errno::EINVAL' do
        -> { @server.accept_nonblock }.should raise_error(Errno::EINVAL)
      end
    end

    describe "using a bound socket that's not listening" do
      before do
        @server.bind(@sockaddr)
      end

      it 'raises Errno::EINVAL' do
        -> { @server.accept_nonblock }.should raise_error(Errno::EINVAL)
      end
    end

    describe 'using a closed socket' do
      it 'raises IOError' do
        @server.close

        -> { @server.accept_nonblock }.should raise_error(IOError)
      end
    end

    describe "using a bound socket that's listening" do
      before do
        @server.bind(@sockaddr)
        @server.listen(1)
      end

      describe 'without a connected client' do
        it 'raises IO::WaitReadable' do
          -> { @server.accept_nonblock }.should raise_error(IO::WaitReadable)
        end
      end

      platform_is_not :windows do
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
            IO.select([@server])
            @socket, addrinfo = @server.accept_nonblock

            @socket.should be_an_instance_of(Socket)
            addrinfo.should be_an_instance_of(Addrinfo)
          end

          describe 'the returned Addrinfo' do
            before do
              IO.select([@server])
              @socket, @addr = @server.accept_nonblock
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
end
