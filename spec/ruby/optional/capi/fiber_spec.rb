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

  ruby_version_is '3.1' do
    describe "rb_fiber_raise" do
      it "raises an exception on the resumed fiber" do
        fiber = Fiber.new do
          begin
            Fiber.yield
          rescue => error
            error
          end
        end

        fiber.resume

        result = @s.rb_fiber_raise(fiber, "Boom!")
        result.should be_an_instance_of(RuntimeError)
        result.message.should == "Boom!"
      end

      it "raises an exception on the transferred fiber" do
        main = Fiber.current

        fiber = Fiber.new do
          begin
            main.transfer
          rescue => error
            error
          end
        end

        fiber.transfer

        result = @s.rb_fiber_raise(fiber, "Boom!")
        result.should be_an_instance_of(RuntimeError)
        result.message.should == "Boom!"
      end
    end
  end
end
