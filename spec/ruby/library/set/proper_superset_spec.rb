require_relative '../../spec_helper'
require_relative 'fixtures/set_like'
require 'set'

describe "Set#proper_superset?" do
  before :each do
    @set = Set[1, 2, 3, 4]
  end

  it "returns true if passed a Set that self is a proper superset of" do
    @set.proper_superset?(Set[]).should be_true
    Set[1, 2, 3].proper_superset?(Set[]).should be_true
    Set["a", :b, ?c].proper_superset?(Set[]).should be_true

    @set.proper_superset?(Set[1, 2, 3]).should be_true
    @set.proper_superset?(Set[1, 3]).should be_true
    @set.proper_superset?(Set[1, 2]).should be_true
    @set.proper_superset?(Set[1]).should be_true

    @set.proper_superset?(Set[5]).should be_false
    @set.proper_superset?(Set[1, 5]).should be_false
    @set.proper_superset?(Set[nil]).should be_false
    @set.proper_superset?(Set["test"]).should be_false

    @set.proper_superset?(@set).should be_false
    Set[].proper_superset?(Set[]).should be_false
  end

  it "raises an ArgumentError when passed a non-Set" do
    -> { Set[].proper_superset?([]) }.should raise_error(ArgumentError)
    -> { Set[].proper_superset?(1) }.should raise_error(ArgumentError)
    -> { Set[].proper_superset?("test") }.should raise_error(ArgumentError)
    -> { Set[].proper_superset?(Object.new) }.should raise_error(ArgumentError)
  end

  context "when comparing to a Set-like object" do
    it "returns true if passed a Set-like object that self is a proper superset of" do
      Set[1, 2, 3, 4].proper_superset?(SetSpecs::SetLike.new([1, 2, 3])).should be_true
    end
  end
end
