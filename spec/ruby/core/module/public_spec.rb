require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/set_visibility'

describe "Module#public" do
  it_behaves_like :set_visibility, :public

  it "on a superclass method calls the redefined method" do
    ModuleSpecs::ChildPrivateMethodMadePublic.new.private_method_redefined.should == :after_redefinition
  end

  it "makes a private Object instance method public in a new module" do
    m = Module.new do
      public :module_specs_private_method_on_object
    end

    m.should have_public_instance_method(:module_specs_private_method_on_object)

    # Ensure we did not change Object's method
    Object.should_not have_public_instance_method(:module_specs_private_method_on_object)
  end

  it "makes a private Object instance method public in Kernel" do
    Kernel.should have_public_instance_method(
                  :module_specs_private_method_on_object_for_kernel_public)
    Object.should_not have_public_instance_method(
                  :module_specs_private_method_on_object_for_kernel_public)
  end

  it "returns self" do
    (class << Object.new; self; end).class_eval do
      def foo; end
      private :foo
      public(:foo).should equal(self)
      public.should equal(self)
    end
  end

  it "raises a NameError when given an undefined name" do
    lambda do
      Module.new.send(:public, :undefined)
    end.should raise_error(NameError)
  end
end
