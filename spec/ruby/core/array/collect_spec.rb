require_relative '../../spec_helper'

describe "Array#collect" do
  it "is an alias of Array#map" do
    Array.instance_method(:collect).should == Array.instance_method(:map)
  end
end

describe "Array#collect!" do
  it "is an alias of Array#map!" do
    Array.instance_method(:collect!).should == Array.instance_method(:map!)
  end
end
