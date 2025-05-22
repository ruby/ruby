require_relative '../../spec_helper'

describe "Refinement#include" do
  it "raises a TypeError" do
    Module.new do
      refine String do
        -> {
          include Module.new
        }.should raise_error(TypeError, "Refinement#include has been removed")
      end
    end
  end
end
