require_relative '../../spec_helper'

describe "Time#tv_usec" do
  it "is an alias of Time#usec" do
    Time.instance_method(:tv_usec).should == Time.instance_method(:usec)
  end
end
