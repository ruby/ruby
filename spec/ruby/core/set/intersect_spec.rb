require_relative '../../spec_helper'
require_relative 'fixtures/set_like'

describe "Set#intersect?" do
  it "returns true when two Sets have at least one element in common" do
    Set[1, 2].intersect?(Set[2, 3]).should == true
  end

  it "returns false when two Sets have no element in common" do
    Set[1, 2].intersect?(Set[3, 4]).should == false
  end

  context "when comparing to a Set-like object" do
    it "returns true when a Set has at least one element in common with a Set-like object" do
      Set[1, 2].intersect?(SetSpecs::SetLike.new([2, 3])).should be_true
    end

    it "returns false when a Set has no element in common with a Set-like object" do
      Set[1, 2].intersect?(SetSpecs::SetLike.new([3, 4])).should be_false
    end
  end
end
