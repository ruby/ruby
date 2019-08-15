require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#public_method_defined?" do
  it "returns true if the named public method is defined by module or its ancestors" do
    ModuleSpecs::CountsMixin.public_method_defined?("public_3").should == true

    ModuleSpecs::CountsParent.public_method_defined?("public_3").should == true
    ModuleSpecs::CountsParent.public_method_defined?("public_2").should == true

    ModuleSpecs::CountsChild.public_method_defined?("public_3").should == true
    ModuleSpecs::CountsChild.public_method_defined?("public_2").should == true
    ModuleSpecs::CountsChild.public_method_defined?("public_1").should == true
  end

  it "returns false if method is not a public method" do
    ModuleSpecs::CountsChild.public_method_defined?("private_3").should == false
    ModuleSpecs::CountsChild.public_method_defined?("private_2").should == false
    ModuleSpecs::CountsChild.public_method_defined?("private_1").should == false

    ModuleSpecs::CountsChild.public_method_defined?("protected_3").should == false
    ModuleSpecs::CountsChild.public_method_defined?("protected_2").should == false
    ModuleSpecs::CountsChild.public_method_defined?("protected_1").should == false
  end

  it "returns false if the named method is not defined by the module or its ancestors" do
    ModuleSpecs::CountsMixin.public_method_defined?(:public_10).should == false
  end

  it "accepts symbols for the method name" do
    ModuleSpecs::CountsMixin.public_method_defined?(:public_3).should == true
  end

  it "raises a TypeError if passed a Fixnum" do
    -> do
      ModuleSpecs::CountsMixin.public_method_defined?(1)
    end.should raise_error(TypeError)
  end

  it "raises a TypeError if passed nil" do
    -> do
      ModuleSpecs::CountsMixin.public_method_defined?(nil)
    end.should raise_error(TypeError)
  end

  it "raises a TypeError if passed false" do
    -> do
      ModuleSpecs::CountsMixin.public_method_defined?(false)
    end.should raise_error(TypeError)
  end

  it "raises a TypeError if passed an object that does not defined #to_str" do
    -> do
      ModuleSpecs::CountsMixin.public_method_defined?(mock('x'))
    end.should raise_error(TypeError)
  end

  it "raises a TypeError if passed an object that defines #to_sym" do
    sym = mock('symbol')
    def sym.to_sym() :public_3 end

    -> do
      ModuleSpecs::CountsMixin.public_method_defined?(sym)
    end.should raise_error(TypeError)
  end

  it "calls #to_str to convert an Object" do
    str = mock('public_3')
    def str.to_str() 'public_3' end
    ModuleSpecs::CountsMixin.public_method_defined?(str).should == true
  end
end
