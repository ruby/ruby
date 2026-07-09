require_relative '../../spec_helper'

describe "Enumerable#filter" do
  it "is an alias of Enumerable#select" do
    Enumerable.instance_method(:filter).should == Enumerable.instance_method(:select)
  end
end
