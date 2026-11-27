require_relative '../../spec_helper'

describe "Time#mday" do
  it "is an alias of Time#day" do
    Time.instance_method(:mday).should == Time.instance_method(:day)
  end
end
