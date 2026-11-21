require_relative '../../spec_helper'
require_relative '../../shared/queue/deque'
require_relative '../../shared/types/rb_num2dbl_fails'

describe "Queue#pop" do
  it_behaves_like :queue_deq, :pop, -> { Queue.new }
end

describe "Queue operations with timeout" do
  it_behaves_like :rb_num2dbl_fails, nil, -> v { q = Queue.new; q.push(1); q.pop(timeout: v) }
end

describe "Queue#pop with Fiber scheduler" do
  require_relative '../fiber/fixtures/scheduler'

  before :each do
    Fiber.set_scheduler(FiberSpecs::LoggingScheduler.new)
  end

  after :each do
    Fiber.set_scheduler(nil)
  end

  it "blocks through the scheduler while the queue is empty" do
    q = Queue.new
    result = nil
    popper = Fiber.schedule { result = q.pop }

    Fiber.scheduler.events.last.should == { event: :block, fiber: popper, args: [q, nil] }
    q.num_waiting.should == 1

    pusher = Fiber.schedule { q << 42 }
    Fiber.scheduler.events.last.should == { event: :unblock, fiber: pusher, args: [q, popper] }

    [pusher, popper].each { |f| f.resume while f.alive? }
    result.should == 42
  end
end
