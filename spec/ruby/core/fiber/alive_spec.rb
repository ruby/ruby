require_relative '../../spec_helper'

describe "Fiber#alive?" do
  it "returns true for a Fiber that hasn't had #resume called" do
    fiber = Fiber.new { true }
    fiber.alive?.should == true
  end

  # FIXME: Better description?
  it "returns true for a Fiber that's yielded to the caller" do
    fiber = Fiber.new { Fiber.yield }
    fiber.resume
    fiber.alive?.should == true
  end

  it "returns true when called from its Fiber" do
    fiber = Fiber.new { fiber.alive?.should == true }
    fiber.resume
  end

  it "doesn't invoke the block associated with the Fiber" do
    offthehook = mock('do not call')
    offthehook.should_not_receive(:ring)
    fiber = Fiber.new { offthehook.ring }
    fiber.alive?
  end

  it "returns false for a Fiber that's dead" do
    fiber = Fiber.new { true }
    fiber.resume
    -> { fiber.resume }.should.raise(FiberError)
    fiber.alive?.should == false
  end

  it "always returns false for a dead Fiber" do
    fiber = Fiber.new { true }
    fiber.resume
    -> { fiber.resume }.should.raise(FiberError)
    fiber.alive?.should == false
    -> { fiber.resume }.should.raise(FiberError)
    fiber.alive?.should == false
    fiber.alive?.should == false
  end
end
