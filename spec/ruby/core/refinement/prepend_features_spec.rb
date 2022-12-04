require_relative '../../spec_helper'

describe "Refinement#prepend_features" do
  ruby_version_is "3.2" do
    it "is not defined" do
      Refinement.should_not have_private_instance_method(:prepend_features)
    end

    it "is not called by Module#prepend" do
      c = Class.new
      Module.new do
        refine c do
          called = false
          define_method(:prepend_features){called = true}
          proc{c.prepend(self)}.should raise_error(TypeError)
          called.should == false
        end
      end
    end
  end
end
