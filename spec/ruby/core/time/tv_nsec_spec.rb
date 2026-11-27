require_relative '../../spec_helper'

describe "Time#tv_nsec" do
  it "is an alias of Time#nsec" do
    Time.instance_method(:tv_nsec).should == Time.instance_method(:nsec)
  end
end
