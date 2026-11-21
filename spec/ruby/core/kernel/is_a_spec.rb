require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#is_a?" do
  before :each do
    @o = KernelSpecs::KindaClass.new
  end

  it "returns true if given class is the object's class" do
    @o.is_a?(KernelSpecs::KindaClass).should == true
  end

  it "returns true if given class is an ancestor of the object's class" do
    @o.is_a?(KernelSpecs::AncestorClass).should == true
    @o.is_a?(String).should == true
    @o.is_a?(Object).should == true
  end

  it "returns false if the given class is not object's class nor an ancestor" do
    @o.is_a?(Array).should == false
  end

  it "returns true if given a Module that is included in object's class" do
    @o.is_a?(KernelSpecs::MyModule).should == true
  end

  it "returns true if given a Module that is included one of object's ancestors only" do
    @o.is_a?(KernelSpecs::AncestorModule).should == true
  end

  it "returns true if given a Module that object has been extended with" do
    @o.is_a?(KernelSpecs::MyExtensionModule).should == true
  end

  it "returns true if given a Module that object has been prepended with" do
    @o.is_a?(KernelSpecs::MyPrependedModule).should == true
  end

  it "returns false if given a Module not included nor prepended in object's class nor ancestors" do
    @o.is_a?(KernelSpecs::SomeOtherModule).should == false
  end

  it "raises a TypeError if given an object that is not a Class nor a Module" do
    -> { @o.is_a?(1) }.should.raise(TypeError)
    -> { @o.is_a?('KindaClass') }.should.raise(TypeError)
    -> { @o.is_a?(:KindaClass) }.should.raise(TypeError)
    -> { @o.is_a?(Object.new) }.should.raise(TypeError)
  end

  it "does not take into account `class` method overriding" do
    def @o.class; Integer; end

    @o.is_a?(Integer).should == false
    @o.is_a?(KernelSpecs::KindaClass).should == true
  end
end
