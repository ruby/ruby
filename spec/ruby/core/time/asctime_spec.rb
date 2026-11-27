require_relative '../../spec_helper'

describe "Time#asctime" do
  it "returns a canonical string representation of time" do
    t = Time.now
    t.asctime.should == t.strftime("%a %b %e %H:%M:%S %Y")
  end
end
