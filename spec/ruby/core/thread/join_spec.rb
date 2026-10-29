require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Thread#join" do
  it "returns the thread when it is finished" do
    t = Thread.new {}
    t.join.should.equal?(t)
  end

  it "returns the thread when it is finished when given a timeout" do
    t = Thread.new {}
    t.join
    t.join(0).should.equal?(t)
  end

  it "coerces timeout to a Float if it is not nil" do
    t = Thread.new {}
    t.join
    t.join(0).should.equal?(t)
    t.join(0.0).should.equal?(t)
    t.join(nil).should.equal?(t)
  end

  it "raises TypeError if the argument is not a valid timeout" do
    t = Thread.new { }
    t.join
    -> { t.join(:foo) }.should.raise TypeError
    -> { t.join("bar") }.should.raise TypeError
  end

  it "returns nil if it is not finished when given a timeout" do
    q = Queue.new
    t = Thread.new { q.pop }
    begin
      t.join(0).should == nil
    ensure
      q << true
    end
    t.join.should == t
  end

  it "accepts a floating point timeout length" do
    q = Queue.new
    t = Thread.new { q.pop }
    begin
      t.join(0.01).should == nil
    ensure
      q << true
    end
    t.join.should == t
  end

  it "raises any exceptions encountered in the thread body" do
    t = Thread.new {
      Thread.current.report_on_exception = false
      raise NotImplementedError.new("Just kidding")
    }
    -> { t.join }.should.raise(NotImplementedError)
  end

  it "returns the dead thread" do
    t = Thread.new { Thread.current.kill }
    t.join.should.equal?(t)
  end

  it "raises any uncaught exception encountered in ensure block" do
    t = ThreadSpecs.dying_thread_ensures { raise NotImplementedError.new("Just kidding") }
    -> { t.join }.should.raise(NotImplementedError)
  end
end

describe "Thread#join with Fiber scheduler" do
  require_relative '../fiber/fixtures/scheduler'

  before :each do
    @queue = Queue.new
    @thread = Thread.new { @queue.pop }
    Thread.pass until @thread.stop?

    @scheduler = Class.new(FiberSpecs::LoggingScheduler) do
      # the finishing thread calls this outside our fibers, so it must not yield
      def unblock(*args)
        @events << { event: :unblock, args: args }
      end
    end.new
    Fiber.set_scheduler(@scheduler)
  end

  after :each do
    Fiber.set_scheduler(nil)
    @queue << :done
    @thread.join
  end

  it "blocks the fiber through the scheduler until the thread finishes" do
    joiner = Fiber.new(blocking: false) { @thread.join }
    joiner.resume
    @scheduler.events.should == [{ event: :block, fiber: joiner, args: [@thread, nil] }]

    @queue << :done
    Thread.pass until @scheduler.events.size == 2
    @scheduler.events.last.should == { event: :unblock, args: [Thread.current, joiner] }

    joiner.resume.should.equal?(@thread)
  end

  it "passes the time left of the timeout to the scheduler" do
    joiner = Fiber.new(blocking: false) { @thread.join(10) }
    joiner.resume

    event = @scheduler.events.last
    event[:event].should == :block
    blocker, timeout = event[:args]
    blocker.should.equal?(@thread)
    ruby_version_is "4.0" do
      timeout.should.is_a?(Float)
    end
    timeout.should <= 10
  end
end
