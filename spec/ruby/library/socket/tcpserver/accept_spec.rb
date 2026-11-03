require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "TCPServer#accept" do
  before :each do
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
  end

  after :each do
    @server.close unless @server.closed?
  end

  it "accepts a connection and returns a TCPSocket" do
    data = nil
    t = Thread.new do
      client = @server.accept
      client.should.is_a?(TCPSocket)
      data = client.read(5)
      client << "goodbye"
      client.close
    end
    Thread.pass while t.status and t.status != "sleep"

    socket = TCPSocket.new('127.0.0.1', @port)
    socket.write('hello')
    socket.shutdown(1) # we are done with sending
    socket.read.should == 'goodbye'
    t.join
    data.should == 'hello'
    socket.close
  end

  it "can be interrupted by Thread#kill" do
    t = Thread.new { @server.accept }

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

  it "is automatically retried when interrupted by SIGVTALRM" do
    t = Thread.new do
      client = @server.accept
      value = client.read(2)
      client.close
      value
    end

    Thread.pass while t.status and t.status != "sleep"
    # Thread#backtrace uses SIGVTALRM on TruffleRuby and potentially other implementations.
    # Sending a signal to a thread is not possible with Ruby APIs.
    t.backtrace.join("\n").should =~ /in [`'](?:TCPServer#)?accept'/

    socket = TCPSocket.new('127.0.0.1', @port)
    socket.write("OK")
    socket.close

    t.value.should == "OK"
  end

  it "raises an IOError if the socket is closed" do
    @server.close
    -> { @server.accept }.should.raise(IOError)
  end
end

describe 'TCPServer#accept' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server = TCPServer.new(ip_address, 0)
    end

    after do
      @server.close
    end

    describe 'without a connected client' do
      it 'blocks the caller' do
        -> { @server.accept }.should block_caller
      end
    end

    describe 'with a connected client' do
      before do
        @client = TCPSocket.new(ip_address, @server.connect_address.ip_port)
      end

      after do
        @socket.close if @socket
        @client.close
      end

      it 'returns a TCPSocket' do
        @socket = @server.accept
        @socket.should.instance_of?(TCPSocket)
      end

      platform_is_not :windows do
        it "returns a TCPSocket which is set to nonblocking" do
          require 'io/nonblock'
          @socket = @server.accept
          @socket.should.nonblock?
        end
      end

      it "returns a TCPSocket which is set to close on exec" do
        @socket = @server.accept
        @socket.should.close_on_exec?
      end
    end
  end
end

platform_is_not :windows do # Hangs on Windows
describe "TCPServer#accept with Fiber scheduler" do
  require_relative '../../../core/fiber/fixtures/scheduler'

  before :each do
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.connect_address.ip_port
    Fiber.set_scheduler(FiberSpecs::LoggingScheduler.new)
  end

  # The server cannot be closed while a fiber waits on it, and the scheduler
  # leaves the fiber parked inside #io_wait, so end its accept before closing:
  # #io_wait returning false makes accept raise IO::TimeoutError.
  after :each do
    @closer.resume if @closer&.alive?
    begin
      @fiber.resume(false) if @fiber&.alive?
    rescue IOError
    end
    @closer.resume if @closer&.alive?
    Fiber.set_scheduler(nil)
    @socket&.close
    @client&.close
    @server.close unless @server.closed?
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
    @client = TCPSocket.new("127.0.0.1", @port)
    IO.select([@server])

    @socket = @fiber.resume(IO::READABLE)
    @socket.should.instance_of?(TCPSocket)
    @client.write("hello")
    @socket.read(5).should == "hello"
  end

  it "accepts a pending connection without calling #io_wait" do
    @client = TCPSocket.new("127.0.0.1", @port)
    IO.select([@server])

    @fiber = Fiber.new(blocking: false) { @server.accept }
    @socket = @fiber.resume
    @socket.should.instance_of?(TCPSocket)
    Fiber.scheduler.events.should == []
  end

  ruby_version_is "3.4" do
    it "calls #io_wait again when it reports the server readable but no connection is pending" do
      @fiber = Fiber.new(blocking: false) { @server.accept }
      @fiber.resume
      @fiber.resume(IO::READABLE)

      io_wait = { event: :io_wait, fiber: @fiber, args: [@server, IO::READABLE, nil] }
      Fiber.scheduler.events.should == [io_wait, io_wait]
    end
  end

  it "raises Errno::EAGAIN when #io_wait returns nil" do
    @fiber = Fiber.new(blocking: false) { @server.accept }
    @fiber.resume

    -> { @fiber.resume(nil) }.should.raise(Errno::EAGAIN, /accept\(2\)/) { |e| e.should.instance_of?(Errno::EAGAIN) }
  end

  ruby_version_is "3.4" do
    it "raises IO::TimeoutError when #io_wait returns false" do
      @fiber = Fiber.new(blocking: false) { @server.accept }
      @fiber.resume

      -> { @fiber.resume(false) }.should.raise(IO::TimeoutError, "Timed out waiting for IO to become readable!")
    end
  end

  ruby_version_is "4.0" do
    it "calls the scheduler's #fiber_interrupt with an IOError when the server is closed while it waits" do
      @fiber = Fiber.new(blocking: false) { @server.accept }
      @fiber.resume
      @closer = Fiber.new(blocking: false) { @server.close }
      @closer.resume

      event = Fiber.scheduler.events.last
      event[:event].should == :fiber_interrupt
      event[:fiber].should == @closer
      ruby_version_is "4.0"..."4.1" do
        event[:args][0].should == @fiber
      end
      event[:args][1].should.instance_of?(IOError)
      event[:args][1].message.should == "stream closed in another thread"

      @closer.resume
      -> { @fiber.resume(IO::READABLE) while @fiber.alive? }.should.raise(IOError)
      @closer.resume
    end
  end

  it "does not call the scheduler if the fiber is blocking" do
    # the root fiber is blocking; the client connects once it waits in #accept
    main = Thread.current
    connector = Thread.new do
      Thread.pass until main.status == "sleep"
      TCPSocket.new("127.0.0.1", @port)
    end

    @socket = @server.accept
    @socket.should.instance_of?(TCPSocket)
    Fiber.scheduler.events.should == []
  ensure
    @client = connector&.value
  end
end
end
