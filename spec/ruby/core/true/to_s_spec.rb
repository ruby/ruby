require_relative '../../spec_helper'

describe "TrueClass#to_s" do
  it "returns the string 'true'" do
    true.to_s.should == "true"
  end

  it "returns a frozen string" do
    true.to_s.should.frozen?
  end

  it "always returns the same string" do
    true.to_s.should equal(true.to_s)
  end
end
