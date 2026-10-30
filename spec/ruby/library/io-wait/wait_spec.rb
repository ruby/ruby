require_relative '../../spec_helper'
require_relative '../../fixtures/io'
require_relative '../../core/fiber/fixtures/scheduler'

describe "IO#wait" do
  before :each do
    @io = File.new(__FILE__ )

    if /mswin|mingw/ =~ RUBY_PLATFORM
      require 'socket'
      @r, @w = Socket.pair(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    else
      @r, @w = IO.pipe
    end
  end

  after :each do
    @io.close unless @io.closed?

    @r.close unless @r.closed?
    @w.close unless @w.closed?
  end

  context "[events, timeout] passed" do
    it "returns events mask when the READABLE event is ready during the timeout" do
      @w.write('data to read')
      @r.wait(IO::READABLE, 2).should == IO::READABLE
    end

    it "returns events mask when the WRITABLE event is ready during the timeout" do
      @w.wait(IO::WRITABLE, 0).should == IO::WRITABLE
    end

    it "waits for the READABLE event to be ready" do
      @r.wait(IO::READABLE, 0).should == nil

      @w.write('data to read')
      @r.wait(IO::READABLE, 0).should_not == nil
    end

    it "waits for the WRITABLE event to be ready" do
      written_bytes = IOSpec.exhaust_write_buffer(@w)
      @w.wait(IO::WRITABLE, 0).should == nil

      @r.read(written_bytes)
      @w.wait(IO::WRITABLE, 0).should_not == nil
    end

    it "does not report READABLE when there is nothing to read" do
      events = @r.wait(IO::READABLE | IO::WRITABLE, 0) || 0
      (events & IO::READABLE).should == 0
    end

    it "returns nil when the READABLE event is not ready during the timeout" do
      @w.wait(IO::READABLE, 0).should == nil
    end

    it "returns nil when the WRITABLE event is not ready during the timeout" do
      IOSpec.exhaust_write_buffer(@w)
      @w.wait(IO::WRITABLE, 0).should == nil
    end

    it "raises IOError when io is closed (closed stream (IOError))" do
      @io.close
      -> { @io.wait(IO::READABLE, 0) }.should.raise(IOError, "closed stream")
    end

    it "raises ArgumentError when events is not positive" do
      -> { @w.wait(0, 0) }.should.raise(ArgumentError, "Events must be positive integer!")
      -> { @w.wait(-1, 0) }.should.raise(ArgumentError, "Events must be positive integer!")
    end

    it "changes thread status to 'sleep' when waits for READABLE event" do
      t = Thread.new { @r.wait(IO::READABLE, 10) }
      sleep 1
      t.status.should == 'sleep'
      t.kill
      t.join # Thread#kill doesn't wait for the thread to end
    end

    # https://github.com/ruby/ruby/actions/runs/11948300522/job/33305664284?pr=12139
    platform_is_not :windows do
      it "changes thread status to 'sleep' when waits for WRITABLE event" do
        IOSpec.exhaust_write_buffer(@w)

        t = Thread.new { @w.wait(IO::WRITABLE, 10) }
        sleep 1
        t.status.should == 'sleep'
        t.kill
        t.join # Thread#kill doesn't wait for the thread to end
      end
    end

    it "can be interrupted when waiting for READABLE event" do
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      t = Thread.new do
        @r.wait(IO::READABLE, 10)
      end

      Thread.pass until t.stop?
      t.kill
      t.join # Thread#kill doesn't wait for the thread to end

      finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      (finish - start).should < 9
    end

    it "can be interrupted when waiting for WRITABLE event" do
      IOSpec.exhaust_write_buffer(@w)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      t = Thread.new do
        @w.wait(IO::WRITABLE, 10)
      end

      Thread.pass until t.stop?
      t.kill
      t.join # Thread#kill doesn't wait for the thread to end

      finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      (finish - start).should < 9
    end
  end

  context "[timeout, mode] passed" do
    it "accepts :r, :read, :readable mode to check READABLE event" do
      @io.wait(0, :r).should == @io
      @io.wait(0, :read).should == @io
      @io.wait(0, :readable).should == @io
    end

    it "accepts :w, :write, :writable mode to check WRITABLE event" do
      @io.wait(0, :w).should == @io
      @io.wait(0, :write).should == @io
      @io.wait(0, :writable).should == @io
    end

    it "accepts :rw, :read_write, :readable_writable mode to check READABLE and WRITABLE events" do
      @io.wait(0, :rw).should == @io
      @io.wait(0, :read_write).should == @io
      @io.wait(0, :readable_writable).should == @io
    end

    it "accepts a list of modes" do
      @io.wait(0, :r, :w, :rw).should == @io
    end

    it "accepts timeout and mode in any order" do
      @io.wait(0, :r).should == @io
      @io.wait(:r, 0).should == @io
      @io.wait(:r, 0, :w).should == @io
    end

    it "raises ArgumentError when passed wrong Symbol value as mode argument" do
      -> { @io.wait(0, :wrong) }.should.raise(ArgumentError, "unsupported mode: wrong")
    end

    it "raises ArgumentError when several Integer arguments passed" do
      -> { @w.wait(0, 10, :r) }.should.raise(ArgumentError, "timeout given more than once")
    end

    it "raises IOError when io is closed (closed stream (IOError))" do
      @io.close
      -> { @io.wait(0, :r) }.should.raise(IOError, "closed stream")
    end
  end

  context "with a Fiber scheduler" do
    before :each do
      Fiber.set_scheduler(FiberSpecs::LoggingScheduler.new)
    end

    # An IO cannot be closed while a fiber is waiting on it, and the scheduler
    # leaves the fiber parked inside #io_wait, so run it out before the outer
    # after hook closes the pipe.
    after :each do
      @fiber.resume while @fiber&.alive?
      Fiber.set_scheduler(nil)
    end

    it "calls the scheduler's #io_wait with the events and timeout given" do
      @fiber = Fiber.new(blocking: false) { @r.wait(IO::READABLE, 2) }
      @fiber.resume

      Fiber.scheduler.events.should == [
        { event: :io_wait, fiber: @fiber, args: [@r, IO::READABLE, 2] }
      ]
    end

    it "calls the scheduler's #io_wait with IO::READABLE when no events are given" do
      @fiber = Fiber.new(blocking: false) { @r.wait }
      @fiber.resume

      Fiber.scheduler.events.should == [
        { event: :io_wait, fiber: @fiber, args: [@r, IO::READABLE, nil] }
      ]
    end

    it "translates a mode Symbol into the matching events mask" do
      @fiber = Fiber.new(blocking: false) { @r.wait(0.5, :readable_writable) }
      @fiber.resume

      Fiber.scheduler.events.should == [
        { event: :io_wait, fiber: @fiber, args: [@r, IO::READABLE | IO::WRITABLE, 0.5] }
      ]
    end

    it "does not call the scheduler if the fiber is blocking" do
      @fiber = Fiber.new(blocking: true) { @r.wait(IO::READABLE, 0) }
      @fiber.resume

      Fiber.scheduler.events.should == []
    end
  end
end
