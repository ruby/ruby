require File.expand_path('../../../spec_helper', __FILE__)

with_feature :fiber_library do
  require 'fiber'

  describe "Fiber.current" do
    it "returns the root Fiber when called outside of a Fiber" do
      root = Fiber.current
      root.should be_an_instance_of(Fiber)
      # We can always transfer to the root Fiber; it will never die
      5.times do
        root.transfer.should be_nil
        root.alive?.should be_true
      end
    end

    it "returns the current Fiber when called from a Fiber" do
      fiber = Fiber.new do
        this = Fiber.current
        this.should be_an_instance_of(Fiber)
        this.should == fiber
        this.alive?.should be_true
      end
      fiber.resume
    end

    it "returns the current Fiber when called from a Fiber that transferred to another" do
      states = []
      fiber = Fiber.new do
        states << :fiber
        this = Fiber.current
        this.should be_an_instance_of(Fiber)
        this.should == fiber
        this.alive?.should be_true
      end

      fiber2 = Fiber.new do
        states << :fiber2
        fiber.transfer
        flunk
      end

      fiber3 = Fiber.new do
        states << :fiber3
        fiber2.transfer
        flunk
      end

      fiber3.resume
      states.should == [:fiber3, :fiber2, :fiber]
    end
  end
end
