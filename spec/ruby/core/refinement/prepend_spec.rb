require_relative '../../spec_helper'

describe "Refinement#prepend" do
  it "raises a TypeError" do
    Module.new do
      refine String do
        -> {
          prepend Module.new
        }.should raise_error(TypeError, "Refinement#prepend has been removed")
      end
    end
  end
end
