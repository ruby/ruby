require_relative '../../spec_helper'

describe "Time.gm" do
  it "is an alias of Time.utc" do
    Time.method(:gm).should == Time.method(:utc)
  end
end
