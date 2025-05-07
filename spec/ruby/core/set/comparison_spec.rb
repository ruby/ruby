require_relative '../../spec_helper'

describe "Set#<=>" do
  it "returns 0 if the sets are equal" do
    (Set[] <=> Set[]).should == 0
    (Set[:a, :b, :c] <=> Set[:a, :b, :c]).should == 0
  end

  it "returns -1 if the set is a proper subset of the other set" do
    (Set[] <=> Set[1]).should == -1
    (Set[1, 2] <=> Set[1, 2, 3]).should == -1
  end

  it "returns +1 if the set is a proper superset of other set" do
    (Set[1] <=> Set[]).should == +1
    (Set[1, 2, 3] <=> Set[1, 2]).should == +1
  end

  it "returns nil if the set has unique elements" do
    (Set[1, 2, 3] <=> Set[:a, :b, :c]).should be_nil
  end

  it "returns nil when the argument is not set-like" do
    (Set[] <=> false).should be_nil
  end
end
