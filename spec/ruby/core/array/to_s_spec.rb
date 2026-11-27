require_relative '../../spec_helper'

describe "Array#to_s" do
  it "is an alias of Array#inspect" do
    Array.instance_method(:to_s).should == Array.instance_method(:inspect)
  end
end
