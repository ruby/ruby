describe :scheduler, shared: true do
  it "validates the scheduler for required methods" do
    required_methods = [:block, :unblock, :kernel_sleep, :io_wait]
    required_methods.each do |missing_method|
      scheduler = Object.new
      required_methods.difference([missing_method]).each do |method|
        scheduler.define_singleton_method(method) {}
      end
      -> {
        suppress_warning { Fiber.set_scheduler(scheduler) }
      }.should raise_error(ArgumentError, /Scheduler must implement ##{missing_method}/)
    end
  end

  it "can set and get the scheduler" do
    required_methods = [:block, :unblock, :kernel_sleep, :io_wait]
    scheduler = Object.new
    required_methods.each do |method|
      scheduler.define_singleton_method(method) {}
    end
    suppress_warning { Fiber.set_scheduler(scheduler) }
    Fiber.scheduler.should == scheduler
  end

  it "returns the scheduler after setting it" do
    required_methods = [:block, :unblock, :kernel_sleep, :io_wait]
    scheduler = Object.new
    required_methods.each do |method|
      scheduler.define_singleton_method(method) {}
    end
    result = suppress_warning { Fiber.set_scheduler(scheduler) }
    result.should == scheduler
  end

  it "can remove the scheduler" do
    required_methods = [:block, :unblock, :kernel_sleep, :io_wait]
    scheduler = Object.new
    required_methods.each do |method|
      scheduler.define_singleton_method(method) {}
    end
    suppress_warning { Fiber.set_scheduler(scheduler) }
    Fiber.set_scheduler(nil)
    Fiber.scheduler.should be_nil
  end

  it "can assign a nil scheduler multiple times" do
    Fiber.set_scheduler(nil)
    Fiber.set_scheduler(nil)
    Fiber.scheduler.should be_nil
  end
end
