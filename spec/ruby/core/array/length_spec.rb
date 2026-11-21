require_relative '../../spec_helper'

describe "Array#length" do
  it "is an alias of Array#size" do
    Array.instance_method(:length).should == Array.instance_method(:size)
  end
end
