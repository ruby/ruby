require_relative '../../spec_helper'

describe "Set#empty?" do
  it "returns true if self is empty" do
    Set[].empty?.should == true
    Set[1].empty?.should == false
    Set[1,2,3].empty?.should == false
  end
end
