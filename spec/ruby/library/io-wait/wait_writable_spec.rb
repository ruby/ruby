require_relative '../../spec_helper'
require_relative '../../fixtures/io'
require_relative '../../core/fiber/fixtures/scheduler'

describe "IO#wait_writable" do
  it "waits for the IO to become writable with no timeout" do
    STDOUT.wait_writable.should == STDOUT
  end

  it "waits for the IO to become writable with the given timeout" do
    STDOUT.wait_writable(1).should == STDOUT
  end

  it "waits for the IO to become writable with the given large timeout" do
    # Represents one year and is larger than a 32-bit int
    STDOUT.wait_writable(365 * 24 * 60 * 60).should == STDOUT
  end

  it "can be interrupted" do
    rd, wr = IO.pipe
    IOSpec.exhaust_write_buffer(wr)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    t = Thread.new do
      wr.wait_writable(10)
    end

    Thread.pass until t.stop?
    t.kill
    t.join

    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    (finish - start).should < 9
  ensure
    rd.close unless rd.closed?
    wr.close unless wr.closed?
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

    it "calls the scheduler's #io_wait with IO::WRITABLE and no timeout" do
      @fiber = Fiber.new(blocking: false) { @write.wait_writable }
      @fiber.resume

      Fiber.scheduler.events.should == [
        { event: :io_wait, fiber: @fiber, args: [@write, IO::WRITABLE, nil] }
      ]
    end

    it "passes the given timeout to the scheduler" do
      @fiber = Fiber.new(blocking: false) { @write.wait_writable(1) }
      @fiber.resume

      Fiber.scheduler.events.should == [
        { event: :io_wait, fiber: @fiber, args: [@write, IO::WRITABLE, 1] }
      ]
    end

    it "does not call the scheduler if the fiber is blocking" do
      @fiber = Fiber.new(blocking: true) { @write.wait_writable(0) }
      @fiber.resume

      Fiber.scheduler.events.should == []
    end
  end
end
