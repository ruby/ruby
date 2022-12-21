require_relative '../../spec_helper'

require 'fiber'

describe "Fiber.new(storage:)" do
  ruby_version_is "3.2" do
    it "creates a Fiber with the given storage" do
      storage = {life: 42}
      fiber = Fiber.new(storage: storage) { Fiber.current.storage }
      fiber.resume.should == storage
    end

    it "creates a fiber with lazily initialized storage" do
      fiber = Fiber.new(storage: nil) {}
      fiber.storage.should == {}
    end

    it "creates a fiber by inheriting the storage of the parent fiber" do
      fiber = Fiber.new(storage: {life: 42}) do
        Fiber.new { Fiber.current.storage }.resume
      end
      fiber.resume.should == {life: 42}
    end

    it "creates a fiber with a reference to the storage of the parent fiber" do
      fiber = Fiber.new(storage: {life: 42}) do
        Fiber.new(storage: false) { Fiber[:life] = 43 }.resume
        Fiber.current.storage
      end
      fiber.resume.should == {life: 43}
    end

    it "cannot create a fiber with non-hash storage" do
      -> { Fiber.new(storage: 42) {} }.should raise_error(TypeError)
    end
  end
end

describe "Fiber#storage" do
  ruby_version_is "3.2" do
    it "can clear the storage of the fiber" do
      fiber = Fiber.new(storage: {life: 42}) { Fiber.current.storage }
      fiber.storage = nil
      fiber.resume.should == {}
    end

    it "can set the storage of the fiber" do
      fiber = Fiber.new(storage: {life: 42}) { Fiber.current.storage }
      fiber.storage = {life: 43}
      fiber.resume.should == {life: 43}
    end

    it "can't set the storage of the fiber to non-hash" do
      fiber = Fiber.new(storage: {life: 42}) { Fiber.current.storage }
      -> { fiber.storage = 42 }.should raise_error(TypeError)
    end

    it "can't set the storage of the fiber to a frozen hash" do
      fiber = Fiber.new(storage: {life: 42}) { Fiber.current.storage }
      -> { fiber.storage = {life: 43}.freeze }.should raise_error(FrozenError)
    end

    it "can't set the storage of the fiber to a hash with non-symbol keys" do
      fiber = Fiber.new(storage: {life: 42}) { Fiber.current.storage }
      -> { fiber.storage = {life: 43, Object.new => 44} }.should raise_error(TypeError)
    end
  end
end

describe "Fiber.[]" do
  ruby_version_is "3.2" do
    it "returns the value of the given key in the storage of the current fiber" do
      Fiber.new(storage: {life: 42}) { Fiber[:life] }.resume.should == 42
    end

    it "returns nil if the key is not present in the storage of the current fiber" do
      Fiber.new(storage: {life: 42}) { Fiber[:death] }.resume.should be_nil
    end

    it "returns nil if the current fiber has no storage" do
      Fiber.new { Fiber[:life] }.resume.should be_nil
    end
  end
end

describe "Fiber.[]=" do
  ruby_version_is "3.2" do
    it "sets the value of the given key in the storage of the current fiber" do
      Fiber.new(storage: {life: 42}) { Fiber[:life] = 43; Fiber[:life] }.resume.should == 43
    end

    it "sets the value of the given key in the storage of the current fiber" do
      Fiber.new(storage: {life: 42}) { Fiber[:death] = 43; Fiber[:death] }.resume.should == 43
    end

    it "sets the value of the given key in the storage of the current fiber" do
      Fiber.new { Fiber[:life] = 43; Fiber[:life] }.resume.should == 43
    end
  end
end

describe "Thread.new" do
  ruby_version_is "3.2" do
    it "creates a thread with the storage of the current fiber" do
      fiber = Fiber.new(storage: {life: 42}) do
        Thread.new { Fiber.current.storage }.value
      end
      fiber.resume.should == {life: 42}
    end
  end
end
