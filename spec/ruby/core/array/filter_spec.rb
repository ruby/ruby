require_relative '../../spec_helper'

describe "Array#filter" do
  it "is an alias of Array#select" do
    Array.instance_method(:filter).should == Array.instance_method(:select)
  end
end

describe "Array#filter!" do
  it "is an alias of Array#select!" do
    Array.instance_method(:filter!).should == Array.instance_method(:select!)
  end
end
