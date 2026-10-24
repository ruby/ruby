require_relative '../../spec_helper'
require_relative 'fixtures/scheduler'

describe "Fiber.schedule" do
  describe "when no scheduler is set" do
    it "raises a RuntimeError" do
      Fiber.scheduler.should == nil

      -> {
        Fiber.schedule { }
      }.should.raise(RuntimeError)
    end
  end

  describe "when a scheduler is set" do
    before :each do
      @scheduler = FiberSpecs::LoggingScheduler.new
      Fiber.set_scheduler(@scheduler)
    end

    after :each do
      Fiber.set_scheduler(nil)
    end

    it "calls the scheduler's #fiber hook" do
      Fiber.schedule { }
      @scheduler.events.map { |event| event[:event] }.should == [:fiber]
    end

    it "returns the Fiber which runs the block" do
      scheduled = nil
      fiber = Fiber.schedule { scheduled = Fiber.current }
      fiber.should.equal?(scheduled)
    end

    it "can be called from inside a non-blocking Fiber" do
      inner = nil

      outer = Fiber.new(blocking: false) do
        inner = Fiber.schedule { }
      end
      outer.resume

      inner.should.is_a?(Fiber)
    end

    it "uses the scheduler of the Thread owning the Fiber it is called from" do
      seen = nil

      outer = Fiber.new(blocking: false) do
        Fiber.schedule { seen = Fiber.scheduler }
      end
      outer.resume

      seen.should.equal?(@scheduler)
    end

    it "runs the block in a Fiber which sees the scheduler as its current scheduler" do
      seen = nil

      outer = Fiber.new(blocking: false) do
        Fiber.schedule { seen = Fiber.current_scheduler }
      end
      outer.resume

      seen.should.equal?(@scheduler)
    end
  end
end
