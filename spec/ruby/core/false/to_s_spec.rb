require_relative '../../spec_helper'

describe "FalseClass#to_s" do
  it "returns the string 'false'" do
    false.to_s.should == "false"
  end

  it "returns a frozen string" do
    false.to_s.should.frozen?
  end

  it "always returns the same string" do
    false.to_s.should equal(false.to_s)
  end
end
