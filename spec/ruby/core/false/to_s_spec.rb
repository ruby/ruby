require_relative '../../spec_helper'

describe "FalseClass#to_s" do
  it "returns the string 'false'" do
    false.to_s.should == "false"
  end
end
