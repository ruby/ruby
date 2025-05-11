require_relative '../../spec_helper'

describe "Refinement#extend_object" do
  it "is not defined" do
    Refinement.should_not have_private_instance_method(:extend_object)
  end

  it "is not called by Object#extend" do
    c = Class.new
    Module.new do
      refine c do
        called = false
        define_method(:extend_object) { called = true }
        -> {
          c.extend(self)
        }.should raise_error(TypeError)
        called.should == false
      end
    end
  end
end
