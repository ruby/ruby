require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#class_variables" do
  it "returns an Array with the names of class variables of self" do
    ModuleSpecs::ClassVars::A.class_variables.should include(:@@a_cvar)
    ModuleSpecs::ClassVars::M.class_variables.should include(:@@m_cvar)
  end

  it "returns an Array of Symbols of class variable names defined in a metaclass" do
    obj = mock("metaclass class variable")
    meta = obj.singleton_class
    meta.send :class_variable_set, :@@var, :cvar_value
    meta.class_variables.should == [:@@var]
  end

  it "returns an Array with names of class variables defined in metaclasses" do
    ModuleSpecs::CVars.class_variables.should include(:@@cls, :@@meta)
  end

  it "does not return class variables defined in extended modules" do
    c = Class.new
    c.extend ModuleSpecs::MVars
    c.class_variables.should_not include(:@@mvar)
  end

  it "returns the correct class variables when inherit is given" do
    ModuleSpecs::SubCVars.class_variables(false).should == [:@@sub]
    ModuleSpecs::SubCVars.new.singleton_class.class_variables(false).should == []

    ModuleSpecs::SubCVars.class_variables(true).should == [:@@sub, :@@cls, :@@meta]
    ModuleSpecs::SubCVars.new.singleton_class.class_variables(true).should ==  [:@@sub, :@@cls, :@@meta]
  end
end
