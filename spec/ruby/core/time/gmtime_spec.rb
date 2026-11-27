require_relative '../../spec_helper'

describe "Time#gmtime" do
  it "is an alias of Time#utc" do
    Time.instance_method(:gmtime).should == Time.instance_method(:utc)
  end
end
