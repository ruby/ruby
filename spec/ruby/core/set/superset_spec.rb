require_relative '../../spec_helper'
require_relative 'fixtures/set_like'

describe "Set#superset?" do
  before :each do
    @set = Set[1, 2, 3, 4]
  end

  it "returns true if passed a Set that equals self or self is a proper superset of" do
    @set.superset?(@set).should == true
    Set[].superset?(Set[]).should == true

    @set.superset?(Set[]).should == true
    Set[1, 2, 3].superset?(Set[]).should == true
    Set["a", :b, ?c].superset?(Set[]).should == true

    @set.superset?(Set[1, 2, 3]).should == true
    @set.superset?(Set[1, 3]).should == true
    @set.superset?(Set[1, 2]).should == true
    @set.superset?(Set[1]).should == true

    @set.superset?(Set[5]).should == false
    @set.superset?(Set[1, 5]).should == false
    @set.superset?(Set[nil]).should == false
    @set.superset?(Set["test"]).should == false
  end

  it "raises an ArgumentError when passed a non-Set" do
    -> { Set[].superset?([]) }.should.raise(ArgumentError)
    -> { Set[].superset?(1) }.should.raise(ArgumentError)
    -> { Set[].superset?("test") }.should.raise(ArgumentError)
    -> { Set[].superset?(Object.new) }.should.raise(ArgumentError)
  end

  ruby_version_is ""..."4.0" do
    context "when comparing to a Set-like object" do
      it "returns true if passed a Set-like object that self is a superset of" do
        Set[1, 2, 3, 4].superset?(SetSpecs::SetLike.new([1, 2, 3])).should == true
      end
    end
  end
end
