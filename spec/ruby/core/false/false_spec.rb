require_relative '../../spec_helper'

describe "FalseClass#false?" do
  it "returns true" do
    false.false?.should == true
  end
end
