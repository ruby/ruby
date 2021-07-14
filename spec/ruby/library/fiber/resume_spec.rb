require_relative '../../spec_helper'

require 'fiber'

describe "Fiber#resume" do
  ruby_version_is '' ... '3.0' do
    it "raises a FiberError if the Fiber has transferred control to another Fiber" do
      fiber1 = Fiber.new { true }
      fiber2 = Fiber.new { fiber1.transfer; Fiber.yield }
      fiber2.resume
      -> { fiber2.resume }.should raise_error(FiberError)
    end
  end

  ruby_version_is '3.0' do
    it "can work with Fiber#transfer" do
      fiber1 = Fiber.new { true }
      fiber2 = Fiber.new { fiber1.transfer; Fiber.yield 10 ; Fiber.yield 20; raise }
      fiber2.resume.should == 10
      fiber2.resume.should == 20
    end
  end
end
