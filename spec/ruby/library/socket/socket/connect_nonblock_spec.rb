require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket#connect_nonblock" do
  before :each do
    @hostname = "127.0.0.1"
    @server = TCPServer.new(@hostname, 0) # started, but no accept
    @addr = Socket.sockaddr_in(@server.addr[1], @hostname)
    @socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    @thread = nil
  end

  after :each do
    @socket.close
    @server.close
    @thread.join if @thread
  end

  platform_is_not :solaris do
    it "connects the socket to the remote side" do
      port = nil
      accept = false
      @thread = Thread.new do
        server = TCPServer.new(@hostname, 0)
        port = server.addr[1]
        Thread.pass until accept
        conn = server.accept
        conn << "hello!"
        conn.close
        server.close
      end

      Thread.pass until port

      addr = Socket.sockaddr_in(port, @hostname)
      begin
        @socket.connect_nonblock(addr)
      rescue Errno::EINPROGRESS
      end

      accept = true
      IO.select nil, [@socket]

      begin
        @socket.connect_nonblock(addr)
      rescue Errno::EISCONN
        # Not all OS's use this errno, so we trap and ignore it
      end

      @socket.read(6).should == "hello!"
    end
  end

  platform_is_not :freebsd, :solaris, :aix do
    it "raises Errno::EINPROGRESS when the connect would block" do
      lambda do
        @socket.connect_nonblock(@addr)
      end.should raise_error(Errno::EINPROGRESS)
    end

    it "raises Errno::EINPROGRESS with IO::WaitWritable mixed in when the connect would block" do
      lambda do
        @socket.connect_nonblock(@addr)
      end.should raise_error(IO::WaitWritable)
    end

    it "returns :wait_writable in exceptionless mode when the connect would block" do
      @socket.connect_nonblock(@addr, exception: false).should == :wait_writable
    end
  end
end

describe 'Socket#connect_nonblock' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    describe 'using a DGRAM socket' do
      before do
        @server   = Socket.new(family, :DGRAM)
        @client   = Socket.new(family, :DGRAM)
        @sockaddr = Socket.sockaddr_in(0, ip_address)

        @server.bind(@sockaddr)
      end

      after do
        @client.close
        @server.close
      end

      it 'returns 0 when successfully connected using a String' do
        @client.connect_nonblock(@server.getsockname).should == 0
      end

      it 'returns 0 when successfully connected using an Addrinfo' do
        @client.connect_nonblock(@server.connect_address).should == 0
      end

      it 'raises TypeError when passed an Integer' do
        lambda { @client.connect_nonblock(666) }.should raise_error(TypeError)
      end
    end

    describe 'using a STREAM socket' do
      before do
        @server   = Socket.new(family, :STREAM)
        @client   = Socket.new(family, :STREAM)
        @sockaddr = Socket.sockaddr_in(0, ip_address)
      end

      after do
        @client.close
        @server.close
      end

      platform_is_not :windows do
        it 'raises Errno::EISCONN when already connected' do
          @server.listen(1)
          @client.connect(@server.getsockname).should == 0

          lambda {
            @client.connect_nonblock(@server.getsockname)

            # A second call needed if non-blocking sockets become default
            # XXX honestly I don't expect any real code to care about this spec
            # as it's too implementation-dependent and checking for connect()
            # errors is futile anyways because of TOCTOU
            @client.connect_nonblock(@server.getsockname)
          }.should raise_error(Errno::EISCONN)
        end

        it 'returns 0 when already connected in exceptionless mode' do
          @server.listen(1)
          @client.connect(@server.getsockname).should == 0

          @client.connect_nonblock(@server.getsockname, exception: false).should == 0
        end
      end

      platform_is_not :freebsd, :solaris do
        it 'raises IO:EINPROGRESSWaitWritable when the connection would block' do
          @server.bind(@sockaddr)

          lambda {
            @client.connect_nonblock(@server.getsockname)
          }.should raise_error(IO::EINPROGRESSWaitWritable)
        end
      end
    end
  end
end
