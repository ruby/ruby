require_relative '../../spec_helper'

describe "Time#hash" do
  it "returns an Integer" do
    Time.at(100).hash.should be_an_instance_of(Integer)
  end

  it "is stable" do
    Time.at(1234).hash.should == Time.at(1234).hash
  end
end
