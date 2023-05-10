require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/kernel/raise'

ruby_version_is "3.3" do
  describe "Fiber#kill" do
    it "kills a non-resumed fiber" do
      fiber = Fiber.new{}

      fiber.alive?.should == true

      fiber.kill
      fiber.alive?.should == false
    end

    it "kills a resumed fiber" do
      fiber = Fiber.new{while true; Fiber.yield; end}
      fiber.resume

      fiber.alive?.should == true

      fiber.kill
      fiber.alive?.should == false
    end

    it "executes the ensure block" do
      ensure_executed = false

      fiber = Fiber.new do
        while true; Fiber.yield; end
      ensure
        ensure_executed = true
      end

      fiber.resume
      fiber.kill
      ensure_executed.should == true
    end

    it "repeatedly kills a fiber" do
      fiber = Fiber.new do
        while true; Fiber.yield; end
      ensure
        while true; Fiber.yield; end
      end

      fiber.kill
      fiber.alive?.should == false
    end
  end
end
