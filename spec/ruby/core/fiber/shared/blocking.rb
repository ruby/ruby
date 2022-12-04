describe :non_blocking_fiber, shared: true do
  context "root Fiber of the main thread" do
    it "returns false" do
      fiber = Fiber.new { @method.call }
      blocking = fiber.resume

      blocking.should == false
    end

    it "returns false for blocking: false" do
      fiber = Fiber.new(blocking: false) { @method.call }
      blocking = fiber.resume

      blocking.should == false
    end
  end

  context "root Fiber of a new thread" do
    it "returns false" do
      thread = Thread.new do
        fiber = Fiber.new { @method.call }
        blocking = fiber.resume

        blocking.should == false
      end

      thread.join
    end

    it "returns false for blocking: false" do
      thread = Thread.new do
        fiber = Fiber.new(blocking: false) { @method.call }
        blocking = fiber.resume

        blocking.should == false
      end

      thread.join
    end
  end
end
