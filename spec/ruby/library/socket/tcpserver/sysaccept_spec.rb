require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "TCPServer#sysaccept" do
  before :each do
    @server = TCPServer.new(SocketSpecs.hostname, 0)
    @port = @server.addr[1]
  end

  after :each do
    @server.close unless @server.closed?
  end

  it 'blocks if no connections' do
    -> { @server.sysaccept }.should block_caller
  end

  it 'returns file descriptor of an accepted connection' do
    begin
      sock = TCPSocket.new(SocketSpecs.hostname, @port)

      fd = @server.sysaccept

      fd.should.is_a?(Integer)
    ensure
      sock.close if sock && !sock.closed?
      IO.for_fd(fd).close if fd
    end
  end
end

describe 'TCPServer#sysaccept' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server = TCPServer.new(ip_address, 0)
    end

    after do
      @server.close
    end

    describe 'without a connected client' do
      it 'blocks the caller' do
        -> { @server.sysaccept }.should block_caller
      end
    end

    describe 'with a connected client' do
      before do
        @client = TCPSocket.new(ip_address, @server.connect_address.ip_port)
      end

      after do
        Socket.for_fd(@fd).close if @fd
        @client.close
      end

      it 'returns a new file descriptor as an Integer' do
        @fd = @server.sysaccept

        @fd.should.is_a?(Integer)
        @fd.should_not == @client.fileno
      end
    end
  end
end

platform_is_not :windows do # Hangs on Windows
describe "TCPServer#sysaccept with Fiber scheduler" do
  require_relative '../../../core/fiber/fixtures/scheduler'

  before :each do
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.connect_address.ip_port
    Fiber.set_scheduler(FiberSpecs::LoggingScheduler.new)
  end

  # The server cannot be closed while a fiber waits on it, and the scheduler
  # leaves the fiber parked inside #io_wait, so end its sysaccept before closing:
  # #io_wait returning false makes sysaccept raise IO::TimeoutError.
  after :each do
    begin
      @fiber.resume(false) if @fiber&.alive?
    rescue IO::TimeoutError
    end
    Fiber.set_scheduler(nil)
    @socket&.close
    @client&.close
    @server.close unless @server.closed?
  end

  ruby_version_is "3.4" do
    it "calls the scheduler's #io_wait with IO::READABLE and no timeout" do
      @fiber = Fiber.new(blocking: false) { @server.sysaccept }
      @fiber.resume

      Fiber.scheduler.events.should == [
        { event: :io_wait, fiber: @fiber, args: [@server, IO::READABLE, nil] }
      ]
    end
  end

  it "returns the file descriptor of the connection once #io_wait reports the server readable" do
    @fiber = Fiber.new(blocking: false) { @server.sysaccept }
    @fiber.resume
    @client = TCPSocket.new("127.0.0.1", @port)
    IO.select([@server])

    fd = @fiber.resume(IO::READABLE)
    fd.should.is_a?(Integer)
    @socket = IO.for_fd(fd)
    @client.write("hello")
    @socket.read(5).should == "hello"
  end

  it "does not call the scheduler if the fiber is blocking" do
    # the root fiber is blocking; the client connects once it waits in #sysaccept
    main = Thread.current
    connector = Thread.new do
      Thread.pass until main.status == "sleep"
      TCPSocket.new("127.0.0.1", @port)
    end

    fd = @server.sysaccept
    @socket = IO.for_fd(fd)
    fd.should.is_a?(Integer)
    Fiber.scheduler.events.should == []
  ensure
    @client = connector&.value
  end
end
end
