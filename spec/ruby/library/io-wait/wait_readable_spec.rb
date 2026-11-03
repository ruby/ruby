require_relative '../../spec_helper'
require_relative '../../core/fiber/fixtures/scheduler'

describe "IO#wait_readable" do
  before :each do
    @io = File.new(__FILE__ )
  end

  after :each do
    @io.close
  end

  it "waits for the IO to become readable with no timeout" do
    @io.wait_readable.should == @io
  end

  it "waits for the IO to become readable with the given timeout" do
    @io.wait_readable(1).should == @io
  end

  it "waits for the IO to become readable with the given large timeout" do
    @io.wait_readable(365 * 24 * 60 * 60).should == @io
  end

  it "can be interrupted" do
    rd, wr = IO.pipe
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    t = Thread.new do
      rd.wait_readable(10)
    end

    Thread.pass until t.stop?
    t.kill
    t.join

    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    (finish - start).should < 9
  ensure
    rd.close
    wr.close
  end

  context "with a Fiber scheduler" do
    before :each do
      @read, @write = IO.pipe
      Fiber.set_scheduler(FiberSpecs::LoggingScheduler.new)
    end

    # An IO cannot be closed while a fiber is waiting on it, and the scheduler
    # leaves the fiber parked inside #io_wait, so run it out before closing.
    after :each do
      @fiber.resume while @fiber&.alive?
      Fiber.set_scheduler(nil)
      @read.close unless @read.closed?
      @write.close unless @write.closed?
    end

    it "calls the scheduler's #io_wait with IO::READABLE and no timeout" do
      @fiber = Fiber.new(blocking: false) { @read.wait_readable }
      @fiber.resume

      Fiber.scheduler.events.should == [
        { event: :io_wait, fiber: @fiber, args: [@read, IO::READABLE, nil] }
      ]
    end

    it "passes the given timeout to the scheduler" do
      @fiber = Fiber.new(blocking: false) { @read.wait_readable(1) }
      @fiber.resume

      Fiber.scheduler.events.should == [
        { event: :io_wait, fiber: @fiber, args: [@read, IO::READABLE, 1] }
      ]
    end

    it "does not call the scheduler if the fiber is blocking" do
      @fiber = Fiber.new(blocking: true) { @read.wait_readable(0) }
      @fiber.resume

      Fiber.scheduler.events.should == []
    end
  end
end
