require_relative '../../spec_helper'

describe "Set#^" do
  before :each do
    @set = Set[1, 2, 3, 4]
  end

  it "returns a new Set containing elements that are not in both self and the passed Enumerable" do
    (@set ^ Set[3, 4, 5]).should == Set[1, 2, 5]
    (@set ^ [3, 4, 5]).should == Set[1, 2, 5]
  end

  it "raises an ArgumentError when passed a non-Enumerable" do
    -> { @set ^ 3 }.should.raise(ArgumentError)
    -> { @set ^ Object.new }.should.raise(ArgumentError)
  end

  ruby_version_is ""..."4.0" do
    it "does not retain compare_by_identity flag" do
      @set.compare_by_identity
      (@set ^ Set[3, 4, 5]).compare_by_identity?.should == false
      (@set ^ [3, 4, 5]).compare_by_identity?.should == false
    end
  end
  ruby_version_is "4.0" do
    it "retains compare_by_identity flag" do
      @set.compare_by_identity
      (@set ^ Set[3, 4, 5]).compare_by_identity?.should == true
      (@set ^ [3, 4, 5]).compare_by_identity?.should == true
    end
  end
end
