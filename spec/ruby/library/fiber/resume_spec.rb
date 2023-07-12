require_relative '../../spec_helper'

require 'fiber'

describe "Fiber#resume" do
  it "can work with Fiber#transfer" do
    fiber1 = Fiber.new { true }
    fiber2 = Fiber.new { fiber1.transfer; Fiber.yield 10 ; Fiber.yield 20; raise }
    fiber2.resume.should == 10
    fiber2.resume.should == 20
  end

  it "raises a FiberError if the Fiber attempts to resume a resuming fiber" do
    root_fiber = Fiber.current
    fiber1 = Fiber.new { root_fiber.resume }
    -> { fiber1.resume }.should raise_error(FiberError, /attempt to resume a resuming fiber/)
  end
end
