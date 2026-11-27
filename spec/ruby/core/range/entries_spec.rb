require_relative '../../spec_helper'

describe "Range#entries" do
  it "is an alias of Range#to_a" do
    Range.instance_method(:entries).should == Range.instance_method(:to_a)
  end
end
