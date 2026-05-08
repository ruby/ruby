require_relative '../../spec_helper'

describe "Refinement#extend_object" do
  it "is not defined" do
    Refinement.private_instance_methods(true).should_not.include?(:extend_object)
  end

  it "is not called by Object#extend" do
    c = Class.new
    Module.new do
      refine c do
        called = false
        define_method(:extend_object) { called = true }
        -> {
          c.extend(self)
        }.should.raise(TypeError)
        called.should == false
      end
    end
  end
end
