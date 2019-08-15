require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#private_method_defined?" do
  it "returns true if the named private method is defined by module or its ancestors" do
    ModuleSpecs::CountsMixin.private_method_defined?("private_3").should == true

    ModuleSpecs::CountsParent.private_method_defined?("private_3").should == true
    ModuleSpecs::CountsParent.private_method_defined?("private_2").should == true

    ModuleSpecs::CountsChild.private_method_defined?("private_3").should == true
    ModuleSpecs::CountsChild.private_method_defined?("private_2").should == true
    ModuleSpecs::CountsChild.private_method_defined?("private_1").should == true
  end

  it "returns false if method is not a private method" do
    ModuleSpecs::CountsChild.private_method_defined?("public_3").should == false
    ModuleSpecs::CountsChild.private_method_defined?("public_2").should == false
    ModuleSpecs::CountsChild.private_method_defined?("public_1").should == false

    ModuleSpecs::CountsChild.private_method_defined?("protected_3").should == false
    ModuleSpecs::CountsChild.private_method_defined?("protected_2").should == false
    ModuleSpecs::CountsChild.private_method_defined?("protected_1").should == false
  end

  it "returns false if the named method is not defined by the module or its ancestors" do
    ModuleSpecs::CountsMixin.private_method_defined?(:private_10).should == false
  end

  it "accepts symbols for the method name" do
    ModuleSpecs::CountsMixin.private_method_defined?(:private_3).should == true
  end

  it "raises a TypeError if passed a Fixnum" do
    -> do
      ModuleSpecs::CountsMixin.private_method_defined?(1)
    end.should raise_error(TypeError)
  end

  it "raises a TypeError if passed nil" do
    -> do
      ModuleSpecs::CountsMixin.private_method_defined?(nil)
    end.should raise_error(TypeError)
  end

  it "raises a TypeError if passed false" do
    -> do
      ModuleSpecs::CountsMixin.private_method_defined?(false)
    end.should raise_error(TypeError)
  end

  it "raises a TypeError if passed an object that does not defined #to_str" do
    -> do
      ModuleSpecs::CountsMixin.private_method_defined?(mock('x'))
    end.should raise_error(TypeError)
  end

  it "raises a TypeError if passed an object that defines #to_sym" do
    sym = mock('symbol')
    def sym.to_sym() :private_3 end

    -> do
      ModuleSpecs::CountsMixin.private_method_defined?(sym)
    end.should raise_error(TypeError)
  end

  it "calls #to_str to convert an Object" do
    str = mock('string')
    def str.to_str() 'private_3' end
    ModuleSpecs::CountsMixin.private_method_defined?(str).should == true
  end

  ruby_version_is "2.6" do
    describe "when passed true as a second optional argument" do
      it "performs a lookup in ancestors" do
        ModuleSpecs::Child.private_method_defined?(:public_child, true).should == false
        ModuleSpecs::Child.private_method_defined?(:protected_child, true).should == false
        ModuleSpecs::Child.private_method_defined?(:accessor_method, true).should == false
        ModuleSpecs::Child.private_method_defined?(:private_child, true).should == true

        # Defined in Parent
        ModuleSpecs::Child.private_method_defined?(:public_parent, true).should == false
        ModuleSpecs::Child.private_method_defined?(:protected_parent, true).should == false
        ModuleSpecs::Child.private_method_defined?(:private_parent, true).should == true

        # Defined in Module
        ModuleSpecs::Child.private_method_defined?(:public_module, true).should == false
        ModuleSpecs::Child.private_method_defined?(:protected_module, true).should == false
        ModuleSpecs::Child.private_method_defined?(:private_module, true).should == true

        # Defined in SuperModule
        ModuleSpecs::Child.private_method_defined?(:public_super_module, true).should == false
        ModuleSpecs::Child.private_method_defined?(:protected_super_module, true).should == false
        ModuleSpecs::Child.private_method_defined?(:private_super_module, true).should == true
      end
    end

    describe "when passed false as a second optional argument" do
      it "checks only the class itself" do
        ModuleSpecs::Child.private_method_defined?(:public_child, false).should == false
        ModuleSpecs::Child.private_method_defined?(:protected_child, false).should == false
        ModuleSpecs::Child.private_method_defined?(:accessor_method, false).should == false
        ModuleSpecs::Child.private_method_defined?(:private_child, false).should == true

        # Defined in Parent
        ModuleSpecs::Child.private_method_defined?(:public_parent, false).should == false
        ModuleSpecs::Child.private_method_defined?(:protected_parent, false).should == false
        ModuleSpecs::Child.private_method_defined?(:private_parent, false).should == false

        # Defined in Module
        ModuleSpecs::Child.private_method_defined?(:public_module, false).should == false
        ModuleSpecs::Child.private_method_defined?(:protected_module, false).should == false
        ModuleSpecs::Child.private_method_defined?(:private_module, false).should == false

        # Defined in SuperModule
        ModuleSpecs::Child.private_method_defined?(:public_super_module, false).should == false
        ModuleSpecs::Child.private_method_defined?(:protected_super_module, false).should == false
        ModuleSpecs::Child.private_method_defined?(:private_super_module, false).should == false
      end
    end
  end
end
