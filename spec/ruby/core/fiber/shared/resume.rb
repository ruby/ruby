describe :fiber_resume, shared: true do
  it "can be invoked from the root Fiber" do
    fiber = Fiber.new { :fiber }
    fiber.send(@method).should == :fiber
  end

  it "can be invoked from a different Thread" do
    fiber = Fiber.new { Thread.current }
    thread = Thread.new { fiber.send(@method) }

    thread.value.should.equal? thread
  end

  it "passes control to the beginning of the block on first invocation" do
    invoked = false
    fiber = Fiber.new { invoked = true }
    fiber.send(@method)
    invoked.should == true
  end

  it "returns the last value encountered on first invocation" do
    fiber = Fiber.new { 1+1; true }
    fiber.send(@method).should == true
  end

  it "runs until the end of the block" do
    obj = mock('obj')
    obj.should_receive(:do).once
    fiber = Fiber.new { 1 + 2; a = "glark"; obj.do }
    fiber.send(@method)
  end

  it "accepts any number of arguments" do
    fiber = Fiber.new { |a| }
    -> { fiber.send(@method, *(1..10).to_a) }.should_not.raise
  end

  it "raises a FiberError if the Fiber is dead" do
    fiber = Fiber.new { true }
    fiber.send(@method)
    -> { fiber.send(@method) }.should.raise(FiberError)
  end

  it "raises a LocalJumpError if the block includes a return statement" do
    fiber = Fiber.new { return; }
    -> { fiber.send(@method) }.should.raise(LocalJumpError)
  end

  it "raises a LocalJumpError if the block includes a break statement" do
    fiber = Fiber.new { break; }
    -> { fiber.send(@method) }.should.raise(LocalJumpError)
  end
end
