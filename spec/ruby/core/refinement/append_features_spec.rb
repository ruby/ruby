require_relative '../../spec_helper'

describe "Refinement#append_features" do
  it "is not defined" do
    Refinement.private_instance_methods(true).should_not.include?(:append_features)
  end

  it "is not called by Module#include" do
    c = Class.new
    Module.new do
      refine c do
        called = false
        define_method(:append_features){called = true}
        proc{c.include(self)}.should.raise(TypeError)
        called.should == false
      end
    end
  end
end
