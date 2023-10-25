require_relative '../../spec_helper'

describe "TrueClass#===" do
  it "returns true for true" do
    (true === true).should == true
  end

  it "returns false for non-true object" do
    (true === 1).should == false
    (true === "").should == false
    (true === Object).should == false
  end
end
