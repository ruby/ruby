require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#extend_object" do
  before :each do
    ScratchPad.clear
  end

  it "is a private method" do
    Module.private_instance_methods(false).should.include?(:extend_object)
  end

  describe "on Class" do
    it "is undefined" do
      Class.private_instance_methods(true).should_not.include?(:extend_object)
    end

    it "raises a TypeError if calling after rebinded to Class" do
      -> {
        Module.instance_method(:extend_object).bind(Class.new).call Object.new
      }.should.raise(TypeError)
    end
  end

  it "is called when #extend is called on an object" do
    ModuleSpecs::ExtendObject.should_receive(:extend_object)
    obj = mock("extended object")
    obj.extend ModuleSpecs::ExtendObject
  end

  it "extends the given object with its constants and methods by default" do
    obj = mock("extended direct")
    ModuleSpecs::ExtendObject.send :extend_object, obj

    obj.test_method.should == "hello test"
    obj.singleton_class.const_get(:C).should == :test
  end

  it "is called even when private" do
    obj = mock("extended private")
    obj.extend ModuleSpecs::ExtendObjectPrivate
    ScratchPad.recorded.should == :extended
  end

  describe "when given a frozen object" do
    before :each do
      @receiver = Module.new
      @object = Object.new.freeze
    end

    it "raises a RuntimeError before extending the object" do
      -> { @receiver.send(:extend_object, @object) }.should.raise(RuntimeError)
      @object.should_not.is_a?(@receiver)
    end
  end
end
