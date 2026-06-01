require_relative '../../spec_helper'

describe "Array#size" do
  it "is an alias of Array#length" do
    Array.instance_method(:size).should == Array.instance_method(:length)
  end
end
