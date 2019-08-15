require_relative '../../spec_helper'

describe "Time#gmt?" do
  it "returns true if time represents a time in UTC (GMT)" do
    Time.now.gmt?.should == false
    Time.now.gmtime.gmt?.should == true
  end
end
