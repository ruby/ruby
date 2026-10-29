require_relative '../../spec_helper'

describe "SizedQueue#push" do
  it "is an alias of SizedQueue#<<" do
    SizedQueue.instance_method(:push).should == SizedQueue.instance_method(:<<)
  end
end

describe "SizedQueue#push with Fiber scheduler" do
  require_relative '../fiber/fixtures/scheduler'

  before :each do
    Fiber.set_scheduler(FiberSpecs::LoggingScheduler.new)
  end

  after :each do
    Fiber.set_scheduler(nil)
  end

  it "blocks through the scheduler while the queue is full" do
    q = SizedQueue.new(1)
    q << 1
    pusher = Fiber.schedule { q << 2 }

    Fiber.scheduler.events.last.should == { event: :block, fiber: pusher, args: [q, nil] }

    popper = Fiber.schedule { q.pop.should == 1 }
    Fiber.scheduler.events.last.should == { event: :unblock, fiber: popper, args: [q, pusher] }

    [popper, pusher].each { |f| f.resume while f.alive? }
    q.pop.should == 2
  end

  it "raises ClosedQueueError when the queue is closed while it blocks" do
    q = SizedQueue.new(1)
    q << 1
    error = nil
    pusher = Fiber.schedule do
      q << 2
    rescue ClosedQueueError => e
      error = e
    end

    closer = Fiber.schedule { q.close }
    [closer, pusher].each { |f| f.resume while f.alive? }
    error.should.is_a?(ClosedQueueError)
  end
end
