require_relative '../../spec_helper'
require_relative 'fixtures/set_like'
require 'set'

describe "Set#superset?" do
  before :each do
    @set = Set[1, 2, 3, 4]
  end

  it "returns true if passed a Set that equals self or self is a proper superset of" do
    @set.superset?(@set).should be_true
    Set[].superset?(Set[]).should be_true

    @set.superset?(Set[]).should be_true
    Set[1, 2, 3].superset?(Set[]).should be_true
    Set["a", :b, ?c].superset?(Set[]).should be_true

    @set.superset?(Set[1, 2, 3]).should be_true
    @set.superset?(Set[1, 3]).should be_true
    @set.superset?(Set[1, 2]).should be_true
    @set.superset?(Set[1]).should be_true

    @set.superset?(Set[5]).should be_false
    @set.superset?(Set[1, 5]).should be_false
    @set.superset?(Set[nil]).should be_false
    @set.superset?(Set["test"]).should be_false
  end

  it "raises an ArgumentError when passed a non-Set" do
    -> { Set[].superset?([]) }.should raise_error(ArgumentError)
    -> { Set[].superset?(1) }.should raise_error(ArgumentError)
    -> { Set[].superset?("test") }.should raise_error(ArgumentError)
    -> { Set[].superset?(Object.new) }.should raise_error(ArgumentError)
  end

  ruby_version_is ""..."3.5" do
    context "when comparing to a Set-like object" do
      it "returns true if passed a Set-like object that self is a superset of" do
        Set[1, 2, 3, 4].superset?(SetSpecs::SetLike.new([1, 2, 3])).should be_true
      end
    end
  end
end
