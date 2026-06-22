require_relative '../../spec_helper'

describe "Refinement#prepend_features" do
  it "is not defined" do
    Refinement.private_instance_methods(true).should_not.include?(:prepend_features)
  end

  it "is not called by Module#prepend" do
    c = Class.new
    Module.new do
      refine c do
        called = false
        define_method(:prepend_features){called = true}
        proc{c.prepend(self)}.should.raise(TypeError)
        called.should == false
      end
    end
  end
end
