require_relative '../../spec_helper'

describe "NilClass#===" do
  it "returns true for nil" do
    (nil === nil).should == true
  end

  it "returns false for non-nil object" do
    (nil === 1).should == false
    (nil === "").should == false
    (nil === Object).should == false
  end
end
