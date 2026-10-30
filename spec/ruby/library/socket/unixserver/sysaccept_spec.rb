require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'UNIXServer#sysaccept' do
  before do
    @path   = SocketSpecs.socket_path
    @server = UNIXServer.new(@path)
  end

  after do
    @server.close

    rm_r(@path)
  end

  describe 'without a client' do
    it 'blocks the calling thread' do
      -> { @server.sysaccept }.should block_caller
    end
  end

  describe 'with a client' do
    before do
      @client = UNIXSocket.new(@path)
    end

    after do
      Socket.for_fd(@fd).close if @fd
      @client.close
    end

    describe 'without any data' do
      it 'returns an Integer' do
        @fd = @server.sysaccept
        @fd.should.is_a?(Integer)
      end
    end

    describe 'with data available' do
      before do
        @client.write('hello')
      end

      it 'returns an Integer' do
        @fd = @server.sysaccept
        @fd.should.is_a?(Integer)
      end
    end
  end
end

platform_is_not :windows do # Hangs on Windows
describe "UNIXServer#sysaccept with Fiber scheduler" do
  require_relative '../../../core/fiber/fixtures/scheduler'

  before :each do
    @path = SocketSpecs.socket_path
    @server = UNIXServer.new(@path)
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
    SocketSpecs.rm_socket @path
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
    @client = UNIXSocket.new(@path)

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
      UNIXSocket.new(@path)
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
