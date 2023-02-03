require_relative '../../spec_helper'

describe "FalseClass#===" do
  it "returns true for false" do
    (false === false).should == true
  end

  it "returns false for non-false object" do
    (false === 0).should == false
    (false === "").should == false
    (false === Object).should == false
    (false === nil).should == false
  end
end
