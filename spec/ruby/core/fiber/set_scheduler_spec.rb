require_relative '../../spec_helper'

require "fiber"

describe "Fiber.scheduler" do
  it "validates the scheduler for required methods" do
    required_methods = [:block, :unblock, :kernel_sleep, :io_wait]

    required_methods.each do |missing_method|
      scheduler = Object.new
      required_methods.difference([missing_method]).each do |method|
        scheduler.define_singleton_method(method) {}
      end
      scheduler.define_singleton_method(:fiber_interrupt) {}
      -> {
        Fiber.set_scheduler(scheduler)
      }.should.raise(ArgumentError, /Scheduler must implement ##{missing_method}/)
    end

    ruby_version_is "4.1" do
      scheduler = Object.new
      required_methods.each do |method|
        scheduler.define_singleton_method(method) {}
      end
      -> {
        Fiber.set_scheduler(scheduler)
      }.should.raise(ArgumentError, /Scheduler must implement #blocking_operation_interrupt or #fiber_interrupt/)
    end
  end

  ruby_version_is "4.1" do
    it "accepts blocking_operation_interrupt instead of fiber_interrupt" do
      scheduler = Object.new
      [:block, :unblock, :kernel_sleep, :io_wait, :blocking_operation_interrupt].each do |method|
        scheduler.define_singleton_method(method) {}
      end

      Fiber.set_scheduler(scheduler)
      Fiber.scheduler.should == scheduler
    end
  end

  it "can set and get the scheduler" do
    required_methods = [:block, :unblock, :kernel_sleep, :io_wait, :fiber_interrupt]
    scheduler = Object.new
    required_methods.each do |method|
      scheduler.define_singleton_method(method) {}
    end
    Fiber.set_scheduler(scheduler)
    Fiber.scheduler.should == scheduler
  end

  it "returns the scheduler after setting it" do
    required_methods = [:block, :unblock, :kernel_sleep, :io_wait, :fiber_interrupt]
    scheduler = Object.new
    required_methods.each do |method|
      scheduler.define_singleton_method(method) {}
    end
    result = Fiber.set_scheduler(scheduler)
    result.should == scheduler
  end

  it "can remove the scheduler" do
    required_methods = [:block, :unblock, :kernel_sleep, :io_wait, :fiber_interrupt]
    scheduler = Object.new
    required_methods.each do |method|
      scheduler.define_singleton_method(method) {}
    end
    Fiber.set_scheduler(scheduler)
    Fiber.set_scheduler(nil)
    Fiber.scheduler.should == nil
  end

  it "can assign a nil scheduler multiple times" do
    Fiber.set_scheduler(nil)
    Fiber.set_scheduler(nil)
    Fiber.scheduler.should == nil
  end
end
