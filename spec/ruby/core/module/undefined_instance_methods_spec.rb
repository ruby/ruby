require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#undefined_instance_methods" do
  ruby_version_is "3.2" do
    it "returns methods undefined in the class" do
      methods = ModuleSpecs::UndefinedInstanceMethods::Parent.undefined_instance_methods
      methods.should == [:undefed_method]
    end

    it "returns inherited methods undefined in the class" do
      methods = ModuleSpecs::UndefinedInstanceMethods::Child.undefined_instance_methods
      methods.should include(:parent_method, :another_parent_method)
    end

    it "returns methods from an included module that are undefined in the class" do
      methods = ModuleSpecs::UndefinedInstanceMethods::Grandchild.undefined_instance_methods
      methods.should include(:super_included_method)
    end

    it "does not returns ancestors undefined methods" do
      methods = ModuleSpecs::UndefinedInstanceMethods::Grandchild.undefined_instance_methods
      methods.should_not include(:parent_method, :another_parent_method)
    end
  end
end
