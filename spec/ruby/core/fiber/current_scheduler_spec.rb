require_relative '../../spec_helper'
require_relative 'fixtures/scheduler'

describe "Fiber.current_scheduler" do
  it "returns nil when no scheduler is set" do
    Fiber.scheduler.should == nil
    Fiber.current_scheduler.should == nil
  end

  describe "when a scheduler is set" do
    before :each do
      @scheduler = FiberSpecs::LoggingScheduler.new
      Fiber.set_scheduler(@scheduler)
    end

    after :each do
      Fiber.set_scheduler(nil)
    end

    it "returns nil on the root Fiber, which is blocking" do
      Fiber.current_scheduler.should == nil
    end

    it "returns the scheduler inside a non-blocking Fiber" do
      seen = nil
      Fiber.new(blocking: false) { seen = Fiber.current_scheduler }.resume
      seen.should.equal?(@scheduler)
    end

    it "returns nil inside a blocking Fiber, where Fiber.scheduler still returns the scheduler" do
      seen = nil
      Fiber.new(blocking: true) { seen = [Fiber.scheduler, Fiber.current_scheduler] }.resume
      seen.should == [@scheduler, nil]
    end

    it "returns nil inside a blocking Fiber nested in a non-blocking Fiber" do
      seen = nil
      Fiber.new(blocking: false) do
        Fiber.new(blocking: true) { seen = Fiber.current_scheduler }.resume
      end.resume
      seen.should == nil
    end

    it "returns the scheduler inside a non-blocking Fiber nested in a blocking Fiber" do
      seen = nil
      Fiber.new(blocking: true) do
        Fiber.new(blocking: false) { seen = Fiber.current_scheduler }.resume
      end.resume
      seen.should.equal?(@scheduler)
    end

    it "returns nil inside Fiber.blocking in a non-blocking Fiber" do
      seen = nil
      Fiber.new(blocking: false) { Fiber.blocking { seen = Fiber.current_scheduler } }.resume
      seen.should == nil
    end

    it "returns the scheduler again after Fiber.blocking returns" do
      seen = nil
      Fiber.new(blocking: false) do
        Fiber.blocking { }
        seen = Fiber.current_scheduler
      end.resume
      seen.should.equal?(@scheduler)
    end

    it "returns nil on the root Fiber after a blocking Fiber has finished" do
      Fiber.new(blocking: true) { }.resume
      Fiber.current_scheduler.should == nil
    end

    it "returns nil on the root Fiber after a blocking Fiber has raised" do
      fiber = Fiber.new(blocking: true) { raise "from the fiber" }
      -> { fiber.resume }.should.raise(RuntimeError)
      Fiber.current_scheduler.should == nil
    end

    it "returns nil on the root Fiber after a blocking Fiber has been killed" do
      fiber = Fiber.new(blocking: true) { Fiber.yield }
      fiber.resume
      fiber.kill
      Fiber.current_scheduler.should == nil
    end
  end
end
