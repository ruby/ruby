require_relative '../../spec_helper'

describe "Refinement#prepend" do
  ruby_version_is "3.1"..."3.2" do
    it "warns about deprecation" do
      Module.new do
        refine String do
          -> {
            prepend Module.new
          }.should complain(/warning: Refinement#prepend is deprecated and will be removed in Ruby 3.2/)
        end
      end
    end
  end

  ruby_version_is "3.2" do
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
end
