describe :fiber_resume, shared: true do
  it "can be invoked from the root Fiber" do
   fiber = Fiber.new { :fiber }
   fiber.send(@method).should == :fiber
  end

  it "raises a FiberError if invoked from a different Thread" do
    fiber = Fiber.new { 42 }
    Thread.new do
      -> {
        fiber.send(@method)
      }.should raise_error(FiberError)
    end.join

    # Check the Fiber can still be used
    fiber.send(@method).should == 42
  end

  it "passes control to the beginning of the block on first invocation" do
    invoked = false
    fiber = Fiber.new { invoked = true }
    fiber.send(@method)
    invoked.should be_true
  end

  it "returns the last value encountered on first invocation" do
    fiber = Fiber.new { 1+1; true }
    fiber.send(@method).should be_true
  end

  it "runs until the end of the block" do
    obj = mock('obj')
    obj.should_receive(:do).once
    fiber = Fiber.new { 1 + 2; a = "glark"; obj.do }
    fiber.send(@method)
  end

  it "accepts any number of arguments" do
    fiber = Fiber.new { |a| }
    -> { fiber.send(@method, *(1..10).to_a) }.should_not raise_error
  end

  it "raises a FiberError if the Fiber is dead" do
    fiber = Fiber.new { true }
    fiber.send(@method)
    -> { fiber.send(@method) }.should raise_error(FiberError)
  end

  it "raises a LocalJumpError if the block includes a return statement" do
    fiber = Fiber.new { return; }
    -> { fiber.send(@method) }.should raise_error(LocalJumpError)
  end

  it "raises a LocalJumpError if the block includes a break statement" do
    fiber = Fiber.new { break; }
    -> { fiber.send(@method) }.should raise_error(LocalJumpError)
  end
end
