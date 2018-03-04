require_relative '../../spec_helper'

with_feature :fiber_library do
  require 'fiber'

  describe "Fiber#resume" do
    it "raises a FiberError if the Fiber has transferred control to another Fiber" do
      fiber1 = Fiber.new { true }
      fiber2 = Fiber.new { fiber1.transfer; Fiber.yield }
      fiber2.resume
      lambda { fiber2.resume }.should raise_error(FiberError)
    end
  end
end
