require_relative "../../spec_helper"

describe "Refinement#target" do
  it "returns the class refined by the receiver" do
    refinement_int = nil

    Module.new do
      refine Integer do
        refinement_int = self
      end
    end

    refinement_int.target.should == Integer
  end
end
