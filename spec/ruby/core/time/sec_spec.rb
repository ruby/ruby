require_relative '../../spec_helper'

describe "Time#sec" do
  it "returns the second of the minute(0..60) for time" do
    Time.at(0).sec.should == 0
  end
end
