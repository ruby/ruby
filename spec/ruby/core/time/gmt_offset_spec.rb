require_relative '../../spec_helper'

describe "Time#gmt_offset" do
  it "is an alias of Time#utc_offset" do
    Time.instance_method(:gmt_offset).should == Time.instance_method(:utc_offset)
  end
end
