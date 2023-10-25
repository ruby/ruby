require_relative '../../spec_helper'

describe "Refinement#refined_class" do
  ruby_version_is "3.2"..."3.3" do
    it "returns the class refined by the receiver" do
      refinement_int = nil

      Module.new do
        refine Integer do
          refinement_int = self
        end
      end

      refinement_int.refined_class.should == Integer
    end
  end
end
