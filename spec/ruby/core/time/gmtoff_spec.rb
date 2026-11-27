require_relative '../../spec_helper'

describe "Time#gmtoff" do
  it "is an alias of Time#utc_offset" do
    Time.instance_method(:gmtoff).should == Time.instance_method(:utc_offset)
  end
end
