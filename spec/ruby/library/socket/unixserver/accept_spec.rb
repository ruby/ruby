require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "UNIXServer#accept" do
  before :each do
    @path = SocketSpecs.socket_path
    @server = UNIXServer.open(@path)
  end

  after :each do
    @server.close if @server
    SocketSpecs.rm_socket @path
  end

  it "accepts what is written by the client" do
    client = UNIXSocket.open(@path)

    client.send('hello', 0)

    sock = @server.accept
    begin
      data, info = sock.recvfrom(5)

      data.should == 'hello'
      info.should_not.empty?
    ensure
      sock.close
      client.close
    end
  end

  it "can be interrupted by Thread#kill" do
    t = Thread.new {
      @server.accept
    }
    Thread.pass while t.status and t.status != "sleep"

    # kill thread, ensure it dies in a reasonable amount of time
    t.kill
    a = 0
    while t.alive? and a < 5000
      sleep 0.001
      a += 1
    end
    a.should < 5000
  end

  it "can be interrupted by Thread#raise" do
    t = Thread.new {
      -> {
        @server.accept
      }.should.raise(Exception, "interrupted")
    }

    Thread.pass while t.status and t.status != "sleep"
    t.raise Exception, "interrupted"
    t.join
  end
end

describe 'UNIXServer#accept' do
  before do
    @path = SocketSpecs.socket_path
    @server = UNIXServer.new(@path)
  end

  after do
    @server.close
    rm_r(@path)
  end

  describe 'without a client' do
    it 'blocks the calling thread' do
      -> { @server.accept }.should block_caller
    end
  end

  describe 'with a client' do
    before do
      @client = UNIXSocket.new(@path)
    end

    after do
      @client.close
      @socket.close if @socket
    end

    describe 'without any data' do
      it 'returns a UNIXSocket' do
        @socket = @server.accept
        @socket.should.instance_of?(UNIXSocket)
      end
    end

    describe 'with data available' do
      before do
        @client.write('hello')
      end

      it 'returns a UNIXSocket' do
        @socket = @server.accept
        @socket.should.instance_of?(UNIXSocket)
      end

      describe 'the returned UNIXSocket' do
        it 'can read the data written' do
          @socket = @server.accept
          @socket.recv(5).should == 'hello'
        end

        platform_is_not :windows do
          it "is set to nonblocking" do
            require 'io/nonblock'
            @socket = @server.accept
            @socket.should.nonblock?
          end
        end

        it "is set to close on exec" do
          @socket = @server.accept
          @socket.should.close_on_exec?
        end
      end
    end
  end
end

platform_is_not :windows do # Hangs on Windows
describe "UNIXServer#accept with Fiber scheduler" do
  require_relative '../../../core/fiber/fixtures/scheduler'

  before :each do
    @path = SocketSpecs.socket_path
    @server = UNIXServer.new(@path)
    Fiber.set_scheduler(FiberSpecs::LoggingScheduler.new)
  end

  # The server cannot be closed while a fiber waits on it, and the scheduler
  # leaves the fiber parked inside #io_wait, so end its accept before closing:
  # #io_wait returning false makes accept raise IO::TimeoutError.
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
      @fiber = Fiber.new(blocking: false) { @server.accept }
      @fiber.resume

      Fiber.scheduler.events.should == [
        { event: :io_wait, fiber: @fiber, args: [@server, IO::READABLE, nil] }
      ]
    end
  end

  it "returns the connection once #io_wait reports the server readable" do
    @fiber = Fiber.new(blocking: false) { @server.accept }
    @fiber.resume
    @client = UNIXSocket.new(@path)

    @socket = @fiber.resume(IO::READABLE)
    @socket.should.instance_of?(UNIXSocket)
    @client.write("hello")
    @socket.read(5).should == "hello"
  end

  it "accepts a pending connection without calling #io_wait" do
    @client = UNIXSocket.new(@path)

    @fiber = Fiber.new(blocking: false) { @server.accept }
    @socket = @fiber.resume
    @socket.should.instance_of?(UNIXSocket)
    Fiber.scheduler.events.should == []
  end

  it "does not call the scheduler if the fiber is blocking" do
    # the root fiber is blocking; the client connects once it waits in #accept
    main = Thread.current
    connector = Thread.new do
      Thread.pass until main.status == "sleep"
      UNIXSocket.new(@path)
    end

    @socket = @server.accept
    @socket.should.instance_of?(UNIXSocket)
    Fiber.scheduler.events.should == []
  ensure
    @client = connector&.value
  end
end
end
