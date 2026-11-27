require_relative '../../spec_helper'

describe "Time#mon" do
  it "is an alias of Time#month" do
    Time.instance_method(:mon).should == Time.instance_method(:month)
  end
end
