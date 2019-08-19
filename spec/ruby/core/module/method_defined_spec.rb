require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#method_defined?" do
  it "returns true if a public or private method with the given name is defined in self, self's ancestors or one of self's included modules" do
    # Defined in Child
    ModuleSpecs::Child.method_defined?(:public_child).should == true
    ModuleSpecs::Child.method_defined?("private_child").should == false
    ModuleSpecs::Child.method_defined?(:accessor_method).should == true

    # Defined in Parent
    ModuleSpecs::Child.method_defined?("public_parent").should == true
    ModuleSpecs::Child.method_defined?(:private_parent).should == false

    # Defined in Module
    ModuleSpecs::Child.method_defined?(:public_module).should == true
    ModuleSpecs::Child.method_defined?(:protected_module).should == true
    ModuleSpecs::Child.method_defined?(:private_module).should == false

    # Defined in SuperModule
    ModuleSpecs::Child.method_defined?(:public_super_module).should == true
    ModuleSpecs::Child.method_defined?(:protected_super_module).should == true
    ModuleSpecs::Child.method_defined?(:private_super_module).should == false
  end

  # unlike alias_method, module_function, public, and friends,
  it "does not search Object or Kernel when called on a module" do
    m = Module.new

    m.method_defined?(:module_specs_public_method_on_kernel).should be_false
  end

  it "raises a TypeError when the given object is not a string/symbol/fixnum" do
    c = Class.new
    o = mock('123')

    -> { c.method_defined?(o) }.should raise_error(TypeError)

    o.should_receive(:to_str).and_return(123)
    -> { c.method_defined?(o) }.should raise_error(TypeError)
  end

  it "converts the given name to a string using to_str" do
    c = Class.new { def test(); end }
    (o = mock('test')).should_receive(:to_str).and_return("test")

    c.method_defined?(o).should == true
  end

  ruby_version_is "2.6" do
    # works as method_defined?(method_name)
    describe "when passed true as a second optional argument" do
      it "performs a lookup in ancestors" do
        ModuleSpecs::Child.method_defined?(:public_child, true).should == true
        ModuleSpecs::Child.method_defined?(:protected_child, true).should == true
        ModuleSpecs::Child.method_defined?(:accessor_method, true).should == true
        ModuleSpecs::Child.method_defined?(:private_child, true).should == false

        # Defined in Parent
        ModuleSpecs::Child.method_defined?(:public_parent, true).should == true
        ModuleSpecs::Child.method_defined?(:protected_parent, true).should == true
        ModuleSpecs::Child.method_defined?(:private_parent, true).should == false

        # Defined in Module
        ModuleSpecs::Child.method_defined?(:public_module, true).should == true
        ModuleSpecs::Child.method_defined?(:protected_module, true).should == true
        ModuleSpecs::Child.method_defined?(:private_module, true).should == false

        # Defined in SuperModule
        ModuleSpecs::Child.method_defined?(:public_super_module, true).should == true
        ModuleSpecs::Child.method_defined?(:protected_super_module, true).should == true
        ModuleSpecs::Child.method_defined?(:private_super_module, true).should == false
      end
    end

    describe "when passed false as a second optional argument" do
      it "checks only the class itself" do
        ModuleSpecs::Child.method_defined?(:public_child, false).should == true
        ModuleSpecs::Child.method_defined?(:protected_child, false).should == true
        ModuleSpecs::Child.method_defined?(:accessor_method, false).should == true
        ModuleSpecs::Child.method_defined?(:private_child, false).should == false

        # Defined in Parent
        ModuleSpecs::Child.method_defined?(:public_parent, false).should == false
        ModuleSpecs::Child.method_defined?(:protected_parent, false).should == false
        ModuleSpecs::Child.method_defined?(:private_parent, false).should == false

        # Defined in Module
        ModuleSpecs::Child.method_defined?(:public_module, false).should == false
        ModuleSpecs::Child.method_defined?(:protected_module, false).should == false
        ModuleSpecs::Child.method_defined?(:private_module, false).should == false

        # Defined in SuperModule
        ModuleSpecs::Child.method_defined?(:public_super_module, false).should == false
        ModuleSpecs::Child.method_defined?(:protected_super_module, false).should == false
        ModuleSpecs::Child.method_defined?(:private_super_module, false).should == false
      end
    end
  end
end
