require_relative '../../spec_helper'
require_relative 'fixtures/set_like'
require 'set'

describe "Set#disjoint?" do
  it "returns false when two Sets have at least one element in common" do
    Set[1, 2].disjoint?(Set[2, 3]).should == false
  end

  it "returns true when two Sets have no element in common" do
    Set[1, 2].disjoint?(Set[3, 4]).should == true
  end

  context "when comparing to a Set-like object" do
    it "returns false when a Set has at least one element in common with a Set-like object" do
      Set[1, 2].disjoint?(SetSpecs::SetLike.new([2, 3])).should be_false
    end

    it "returns true when a Set has no element in common with a Set-like object" do
      Set[1, 2].disjoint?(SetSpecs::SetLike.new([3, 4])).should be_true
    end
  end
end
