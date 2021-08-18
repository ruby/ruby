require_relative 'spec_helper'
require 'fiber'

load_extension('fiber')

describe "C-API Fiber function" do
  before :each do
    @s = CApiFiberSpecs.new
  end

  describe "rb_fiber_current" do
    it "returns the current fiber" do
      result = @s.rb_fiber_current()
      result.should be_an_instance_of(Fiber)
      result.should == Fiber.current
    end
  end

  describe "rb_fiber_alive_p" do
    it "returns the fibers alive status" do
      fiber = Fiber.new { Fiber.yield }
      fiber.resume
      @s.rb_fiber_alive_p(fiber).should be_true
      fiber.resume
      @s.rb_fiber_alive_p(fiber).should be_false
    end
  end

  describe "rb_fiber_resume" do
    it "resumes the fiber" do
      fiber = Fiber.new { |arg| Fiber.yield arg }
      @s.rb_fiber_resume(fiber, [1]).should == 1
      @s.rb_fiber_resume(fiber, [2]).should == 2
    end
  end

  describe "rb_fiber_yield" do
    it "yields the fiber" do
      fiber = Fiber.new { @s.rb_fiber_yield([1]) }
      fiber.resume.should == 1
    end
  end

  describe "rb_fiber_new" do
    it "returns a new fiber" do
      fiber = @s.rb_fiber_new
      fiber.should be_an_instance_of(Fiber)
      fiber.resume(42).should == "42"
    end
  end
end
