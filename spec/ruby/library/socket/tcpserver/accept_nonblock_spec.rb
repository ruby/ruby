require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket::TCPServer.accept_nonblock" do
  before :each do
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
  end

  after :each do
    @server.close unless @server.closed?
  end

  it "accepts non blocking connections" do
    @server.listen(5)
    lambda {
      @server.accept_nonblock
    }.should raise_error(IO::WaitReadable)

    c = TCPSocket.new("127.0.0.1", @port)
    sleep 0.1
    s = @server.accept_nonblock

    port, address = Socket.unpack_sockaddr_in(s.getsockname)

    port.should == @port
    address.should == "127.0.0.1"
    s.should be_kind_of(TCPSocket)

    c.close
    s.close
  end

  it "raises an IOError if the socket is closed" do
    @server.close
    lambda { @server.accept }.should raise_error(IOError)
  end

  describe 'without a connected client' do
    it 'raises error' do
      lambda { @server.accept_nonblock }.should raise_error(IO::WaitReadable)
    end

    it 'returns :wait_readable in exceptionless mode' do
      @server.accept_nonblock(exception: false).should == :wait_readable
    end
  end
end

describe 'TCPServer#accept_nonblock' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server = TCPServer.new(ip_address, 0)
    end

    after do
      @server.close
    end

    describe 'without a connected client' do
      it 'raises IO::WaitReadable' do
        lambda { @server.accept_nonblock }.should raise_error(IO::WaitReadable)
      end
    end

    platform_is_not :windows do # spurious
      describe 'with a connected client' do
        before do
          @client = TCPSocket.new(ip_address, @server.connect_address.ip_port)
        end

        after do
          @socket.close if @socket
          @client.close
        end

        it 'returns a TCPSocket' do
          @socket = @server.accept_nonblock
          @socket.should be_an_instance_of(TCPSocket)
        end
      end
    end
  end
end
