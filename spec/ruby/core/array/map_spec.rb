require_relative '../../spec_helper'

describe "Array#map" do
  it "is an alias of Array#collect" do
    Array.instance_method(:map).should == Array.instance_method(:collect)
  end
end

describe "Array#map!" do
  it "is an alias of Array#collect!" do
    Array.instance_method(:map!).should == Array.instance_method(:collect!)
  end
end
