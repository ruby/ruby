require_relative '../../spec_helper'

describe "Enumerable#find_all" do
  it "is an alias of Enumerable#select" do
    Enumerable.instance_method(:find_all).should == Enumerable.instance_method(:select)
  end
end
