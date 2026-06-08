require_relative '../../spec_helper'

describe "Enumerable#entries" do
  it "is an alias of Enumerable#to_a" do
    Enumerable.instance_method(:entries).should == Enumerable.instance_method(:to_a)
  end
end
