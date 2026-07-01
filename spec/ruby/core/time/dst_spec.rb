require_relative '../../spec_helper'

describe "Time#dst?" do
  it "returns whether time is during daylight saving time" do
    with_timezone("America/Los_Angeles") do
      Time.local(2007, 9, 9, 0, 0, 0).dst?.should == true
      Time.local(2007, 1, 9, 0, 0, 0).dst?.should == false
    end
  end
end
