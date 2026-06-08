require_relative '../../spec_helper'

describe "Time#getgm" do
  it "is an alias of Time#getutc" do
    Time.instance_method(:getgm).should == Time.instance_method(:getutc)
  end
end
