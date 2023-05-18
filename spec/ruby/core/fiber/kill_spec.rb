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

    it "can kill itself" do
      fiber = Fiber.new do
        Fiber.current.kill
      end

      fiber.alive?.should == true

      fiber.resume
      fiber.alive?.should == false
    end

    it "kills a resumed fiber from a child" do
      parent = Fiber.new do
        child = Fiber.new do
          parent.kill
          parent.alive?.should == true
        end

        child.resume
      end

      parent.resume
      parent.alive?.should == false
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

    it "does not execute rescue block" do
      rescue_executed = false

      fiber = Fiber.new do
        while true; Fiber.yield; end
      rescue Exception
        rescue_executed = true
      end

      fiber.resume
      fiber.kill
      rescue_executed.should == false
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
