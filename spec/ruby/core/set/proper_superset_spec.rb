require_relative '../../spec_helper'
require_relative 'fixtures/set_like'

describe "Set#proper_superset?" do
  before :each do
    @set = Set[1, 2, 3, 4]
  end

  it "returns true if passed a Set that self is a proper superset of" do
    @set.proper_superset?(Set[]).should == true
    Set[1, 2, 3].proper_superset?(Set[]).should == true
    Set["a", :b, ?c].proper_superset?(Set[]).should == true

    @set.proper_superset?(Set[1, 2, 3]).should == true
    @set.proper_superset?(Set[1, 3]).should == true
    @set.proper_superset?(Set[1, 2]).should == true
    @set.proper_superset?(Set[1]).should == true

    @set.proper_superset?(Set[5]).should == false
    @set.proper_superset?(Set[1, 5]).should == false
    @set.proper_superset?(Set[nil]).should == false
    @set.proper_superset?(Set["test"]).should == false

    @set.proper_superset?(@set).should == false
    Set[].proper_superset?(Set[]).should == false
  end

  it "raises an ArgumentError when passed a non-Set" do
    -> { Set[].proper_superset?([]) }.should.raise(ArgumentError)
    -> { Set[].proper_superset?(1) }.should.raise(ArgumentError)
    -> { Set[].proper_superset?("test") }.should.raise(ArgumentError)
    -> { Set[].proper_superset?(Object.new) }.should.raise(ArgumentError)
  end

  ruby_version_is ""..."4.0" do
    context "when comparing to a Set-like object" do
      it "returns true if passed a Set-like object that self is a proper superset of" do
        Set[1, 2, 3, 4].proper_superset?(SetSpecs::SetLike.new([1, 2, 3])).should == true
      end
    end
  end
end
