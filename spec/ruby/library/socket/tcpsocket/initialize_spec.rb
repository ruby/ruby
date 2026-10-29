require_relative '../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/new'

describe 'TCPSocket#initialize' do
  it_behaves_like :tcpsocket_new, :new

  describe "with a running server" do
    before :each do
      @server = SocketSpecs::SpecTCPServer.new
      @hostname = @server.hostname
    end

    after :each do
      if @socket
        @socket.write "QUIT"
        @socket.close
      end
      @server.shutdown
    end

    it "does not use the given block and warns to use TCPSocket::open" do
      -> {
        @socket = TCPSocket.new(@hostname, @server.port, nil) { raise }
      }.should complain(/warning: TCPSocket::new\(\) does not take block; use TCPSocket::open\(\) instead/)
    end
  end
end

describe 'TCPSocket#initialize' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    describe 'when no server is listening on the given address' do
      it 'raises Errno::ECONNREFUSED' do
        -> { TCPSocket.new(ip_address, 666) }.should.raise(Errno::ECONNREFUSED)
      end
    end

    describe 'when a server is listening on the given address' do
      before do
        @server = TCPServer.new(ip_address, 0)
        @port   = @server.connect_address.ip_port
      end

      after do
        @client.close if @client
        @server.close
      end

      it 'returns a TCPSocket when using an Integer as the port' do
        @client = TCPSocket.new(ip_address, @port)
        @client.should.instance_of?(TCPSocket)
      end

      it 'returns a TCPSocket when using a String as the port' do
        @client = TCPSocket.new(ip_address, @port.to_s)
        @client.should.instance_of?(TCPSocket)
      end

      it 'raises SocketError when the port number is a non numeric String' do
        -> { TCPSocket.new(ip_address, 'cats') }.should.raise(SocketError)
      end

      it 'set the socket to binmode' do
        @client = TCPSocket.new(ip_address, @port)
        @client.binmode?.should == true
      end

      it 'connects to the right address' do
        @client = TCPSocket.new(ip_address, @port)

        @client.remote_address.ip_address.should == @server.local_address.ip_address
        @client.remote_address.ip_port.should    == @server.local_address.ip_port
      end

      platform_is_not :windows do
        it "creates a socket which is set to nonblocking" do
          require 'io/nonblock'
          @client = TCPSocket.new(ip_address, @port)
          @client.should.nonblock?
        end
      end

      it "creates a socket which is set to close on exec" do
        @client = TCPSocket.new(ip_address, @port)
        @client.should.close_on_exec?
      end

      describe 'using a local address and service' do
        it 'binds the client socket to the local address and service' do
          @client = TCPSocket.new(ip_address, @port, ip_address, 0)

          @client.local_address.ip_address.should == ip_address

          @client.local_address.ip_port.should > 0
          @client.local_address.ip_port.should_not == @port
        end
      end
    end
  end
end

# A nonblocking connect to loopback reports EINPROGRESS, as in Socket#connect_nonblock's specs
platform_is_not :windows, :freebsd, :aix do
  describe "TCPSocket#initialize with Fiber scheduler" do
    require_relative '../../../core/fiber/fixtures/scheduler'

    before :each do
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.connect_address.ip_port
      Fiber.set_scheduler(FiberSpecs::LoggingScheduler.new)
    end

    # The scheduler leaves the fiber parked inside #io_wait, so end its connect
    # before closing: #io_wait returning false makes it raise IO::TimeoutError.
    after :each do
      begin
        @fiber.resume(false) if @fiber&.alive?
      rescue IO::TimeoutError
      end
      Fiber.set_scheduler(nil)
      @socket&.close
      @server.close unless @server.closed?
    end

    ruby_version_is "3.4" do
      it "calls the scheduler's #io_wait with IO::READABLE | IO::WRITABLE and no timeout" do
        @fiber = Fiber.new(blocking: false) { TCPSocket.new("127.0.0.1", @port) }
        @fiber.resume

        Fiber.scheduler.events.size.should == 1
        event = Fiber.scheduler.events[0]
        event[:event].should == :io_wait
        event[:fiber].should == @fiber
        event[:args][0].should.instance_of?(TCPSocket)
        event[:args][1..].should == [IO::READABLE | IO::WRITABLE, nil]
      end
    end

    it "passes the connect_timeout to #io_wait" do
      @fiber = Fiber.new(blocking: false) { TCPSocket.new("127.0.0.1", @port, connect_timeout: 2) }
      @fiber.resume

      Fiber.scheduler.events[0][:args][2].should == 2
    end

    it "returns the connected socket once #io_wait returns" do
      @fiber = Fiber.new(blocking: false) { TCPSocket.new("127.0.0.1", @port) }
      @fiber.resume
      IO.select(nil, [Fiber.scheduler.events[0][:args][0]])

      @socket = @fiber.resume(IO::WRITABLE)
      @socket.should.instance_of?(TCPSocket)
      @socket.remote_address.ip_port.should == @port
    end

    ruby_version_is "3.4" do
      it "raises IO::TimeoutError when #io_wait returns false" do
        @fiber = Fiber.new(blocking: false) { TCPSocket.new("127.0.0.1", @port) }
        @fiber.resume

        -> { @fiber.resume(false) }.should.raise(IO::TimeoutError)
      end
    end

    it "raises Errno::ECONNREFUSED once #io_wait returns when no server is listening" do
      @server.close
      @fiber = Fiber.new(blocking: false) { TCPSocket.new("127.0.0.1", @port) }
      begin
        @fiber.resume
      rescue Errno::ECONNREFUSED
        skip "connect(2) was refused synchronously without calling #io_wait"
      end

      IO.select(nil, [Fiber.scheduler.events[0][:args][0]])

      -> { @fiber.resume(IO::WRITABLE) }.should.raise(Errno::ECONNREFUSED)
    end

    it "does not call the scheduler if the fiber is blocking" do
      @socket = TCPSocket.new("127.0.0.1", @port)
      @socket.should.instance_of?(TCPSocket)
      Fiber.scheduler.events.should == []
    end
  end
end
