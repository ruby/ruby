require_relative '../../spec_helper'

ruby_version_is "3.2" do
  describe "Fiber.new(storage:)" do
    it "creates a Fiber with the given storage" do
      storage = {life: 42}
      fiber = Fiber.new(storage: storage) { Fiber.current.storage }
      fiber.resume.should == storage
    end

    it "creates a fiber with lazily initialized storage" do
      Fiber.new(storage: nil) { Fiber[:x] = 10; Fiber.current.storage }.resume.should == {x: 10}
    end

    it "creates a fiber by inheriting the storage of the parent fiber" do
      fiber = Fiber.new(storage: {life: 42}) do
        Fiber.new { Fiber.current.storage }.resume
      end
      fiber.resume.should == {life: 42}
    end

    it "cannot create a fiber with non-hash storage" do
      -> { Fiber.new(storage: 42) {} }.should raise_error(TypeError)
    end

    it "cannot create a fiber with a frozen hash as storage" do
      -> { Fiber.new(storage: {life: 43}.freeze) {} }.should raise_error(FrozenError)
    end

    it "cannot create a fiber with a storage hash with non-symbol keys" do
      -> { Fiber.new(storage: {life: 43, Object.new => 44}) {} }.should raise_error(TypeError)
    end
  end

  describe "Fiber#storage" do
    it "cannot be accessed from a different fiber" do
      f = Fiber.new(storage: {life: 42}) { nil }
      -> {
        f.storage
      }.should raise_error(ArgumentError, /Fiber storage can only be accessed from the Fiber it belongs to/)
    end
  end

  describe "Fiber#storage=" do
    it "can clear the storage of the fiber" do
      fiber = Fiber.new(storage: {life: 42}) do
        Fiber.current.storage = nil
        Fiber[:x] = 10
        Fiber.current.storage
      end
      fiber.resume.should == {x: 10}
    end

    it "can set the storage of the fiber" do
      fiber = Fiber.new(storage: {life: 42}) do
        Fiber.current.storage = {life: 43}
        Fiber.current.storage
      end
      fiber.resume.should == {life: 43}
    end

    it "can't set the storage of the fiber to non-hash" do
      -> { Fiber.current.storage = 42 }.should raise_error(TypeError)
    end

    it "can't set the storage of the fiber to a frozen hash" do
      -> { Fiber.current.storage = {life: 43}.freeze }.should raise_error(FrozenError)
    end

    it "can't set the storage of the fiber to a hash with non-symbol keys" do
      -> { Fiber.current.storage = {life: 43, Object.new => 44} }.should raise_error(TypeError)
    end
  end

  describe "Fiber.[]" do
    it "returns the value of the given key in the storage of the current fiber" do
      Fiber.new(storage: {life: 42}) { Fiber[:life] }.resume.should == 42
    end

    it "returns nil if the key is not present in the storage of the current fiber" do
      Fiber.new(storage: {life: 42}) { Fiber[:death] }.resume.should be_nil
    end

    it "returns nil if the current fiber has no storage" do
      Fiber.new { Fiber[:life] }.resume.should be_nil
    end

    ruby_version_is "3.2.3" do
      it "can use dynamically defined keys" do
        key = :"#{self.class.name}#.#{self.object_id}"
        Fiber.new { Fiber[key] = 42; Fiber[key] }.resume.should == 42
      end
    end

    ruby_bug "#20978", "3.2.3"..."3.4" do
      it "can use keys as strings" do
        key = Object.new
        def key.to_str; "Foo"; end
        Fiber[key] = 42
        Fiber["Foo"].should == 42
      end
    end

    it "can access the storage of the parent fiber" do
      f = Fiber.new(storage: {life: 42}) do
        Fiber.new { Fiber[:life] }.resume
      end
      f.resume.should == 42
    end

    it "can't access the storage of the fiber with non-symbol keys" do
      -> { Fiber[Object.new] }.should raise_error(TypeError)
    end
  end

  describe "Fiber.[]=" do
    it "sets the value of the given key in the storage of the current fiber" do
      Fiber.new(storage: {life: 42}) { Fiber[:life] = 43; Fiber[:life] }.resume.should == 43
    end

    it "sets the value of the given key in the storage of the current fiber" do
      Fiber.new(storage: {life: 42}) { Fiber[:death] = 43; Fiber[:death] }.resume.should == 43
    end

    it "sets the value of the given key in the storage of the current fiber" do
      Fiber.new { Fiber[:life] = 43; Fiber[:life] }.resume.should == 43
    end

    it "does not overwrite the storage of the parent fiber" do
      f = Fiber.new(storage: {life: 42}) do
        Fiber.yield Fiber.new { Fiber[:life] = 43; Fiber[:life] }.resume
        Fiber[:life]
      end
      f.resume.should == 43 # Value of the inner fiber
      f.resume.should == 42 # Value of the outer fiber
    end

    it "can't access the storage of the fiber with non-symbol keys" do
      -> { Fiber[Object.new] = 44 }.should raise_error(TypeError)
    end

    ruby_version_is "3.3" do
      it "deletes the fiber storage key when assigning nil" do
        Fiber.new(storage: {life: 42}) {
          Fiber[:life] = nil
          Fiber.current.storage
        }.resume.should == {}
      end
    end
  end

  describe "Thread.new" do
    it "creates a thread with the storage of the current fiber" do
      fiber = Fiber.new(storage: {life: 42}) do
        Thread.new { Fiber.current.storage }.value
      end
      fiber.resume.should == {life: 42}
    end
  end
end
