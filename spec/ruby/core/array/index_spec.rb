require_relative '../../spec_helper'

describe "Array#index" do
  it "is an alias of Array#find_index" do
    Array.instance_method(:index).should == Array.instance_method(:find_index)
  end
end
