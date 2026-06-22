require_relative '../../spec_helper'

describe "Time#tv_sec" do
  it "is an alias of Time#to_i" do
    Time.instance_method(:tv_sec).should == Time.instance_method(:to_i)
  end
end
