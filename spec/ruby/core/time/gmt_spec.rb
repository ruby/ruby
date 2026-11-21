require_relative '../../spec_helper'

describe "Time#gmt?" do
  it "is an alias of Time#utc?" do
    Time.instance_method(:gmt?).should == Time.instance_method(:utc?)
  end
end
