require_relative '../../spec_helper'

describe "Symbol#empty?" do
  it "returns true if self is empty" do
    :"".empty?.should == true
  end

  it "returns false if self is non-empty" do
    :"a".empty?.should == false
  end
end
