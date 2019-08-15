require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#>=" do
  it "returns true if self is a superclass of, the same as or included by given module" do
    (ModuleSpecs::Parent >= ModuleSpecs::Child).should == true
    (ModuleSpecs::Basic  >= ModuleSpecs::Child).should == true
    (ModuleSpecs::Super  >= ModuleSpecs::Child).should == true
    (ModuleSpecs::Basic  >= ModuleSpecs::Super).should == true
    (ModuleSpecs::Child  >= ModuleSpecs::Child).should == true
    (ModuleSpecs::Parent >= ModuleSpecs::Parent).should == true
    (ModuleSpecs::Basic  >= ModuleSpecs::Basic).should == true
    (ModuleSpecs::Super  >= ModuleSpecs::Super).should == true
  end

  it "returns nil if self is not related to the given module" do
    (ModuleSpecs::Parent >= ModuleSpecs::Basic).should == nil
    (ModuleSpecs::Parent >= ModuleSpecs::Super).should == nil
    (ModuleSpecs::Basic  >= ModuleSpecs::Parent).should == nil
    (ModuleSpecs::Super  >= ModuleSpecs::Parent).should == nil
  end

  it "returns false if self is a subclass of or includes the given module" do
    (ModuleSpecs::Child >= ModuleSpecs::Parent).should == false
    (ModuleSpecs::Child >= ModuleSpecs::Basic).should == false
    (ModuleSpecs::Child >= ModuleSpecs::Super).should == false
    (ModuleSpecs::Super >= ModuleSpecs::Basic).should == false
  end

  it "raises a TypeError if the argument is not a class/module" do
    -> { ModuleSpecs::Parent >= mock('x') }.should raise_error(TypeError)
  end
end
