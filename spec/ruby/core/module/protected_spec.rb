require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/set_visibility'

describe "Module#protected" do
  before :each do
    class << ModuleSpecs::Parent
      def protected_method_1; 5; end
    end
  end

  it_behaves_like :set_visibility, :protected

  it "makes an existing class method protected" do
    ModuleSpecs::Parent.protected_method_1.should == 5

    class << ModuleSpecs::Parent
      protected :protected_method_1
    end

    -> { ModuleSpecs::Parent.protected_method_1 }.should.raise(NoMethodError)
  end

  it "makes a public Object instance method protected in a new module" do
    m = Module.new do
      protected :module_specs_public_method_on_object
    end

    m.protected_instance_methods(false).should.include?(:module_specs_public_method_on_object)

    # Ensure we did not change Object's method
    Object.protected_instance_methods(true).should_not.include?(:module_specs_public_method_on_object)
  end

  it "makes a public Object instance method protected in Kernel" do
    Kernel.protected_instance_methods(false).should.include?(
                  :module_specs_public_method_on_object_for_kernel_protected)
    Object.protected_instance_methods(true).should_not.include?(
                  :module_specs_public_method_on_object_for_kernel_protected)
  end

  it "returns argument or arguments if given" do
    (class << Object.new; self; end).class_eval do
      def foo; end
      protected(:foo).should.equal?(:foo)
      protected([:foo, :foo]).should == [:foo, :foo]
      protected(:foo, :foo).should == [:foo, :foo]
      protected.should.equal?(nil)
    end
  end

  it "raises a NameError when given an undefined name" do
    -> do
      Module.new.send(:protected, :undefined)
    end.should.raise(NameError)
  end
end
