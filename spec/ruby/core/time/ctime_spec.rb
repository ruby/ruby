require_relative '../../spec_helper'

describe "Time#ctime" do
  it "is an alias of Time#asctime" do
    Time.instance_method(:ctime).should == Time.instance_method(:asctime)
  end
end
