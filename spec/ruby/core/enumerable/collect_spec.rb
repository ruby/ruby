require_relative '../../spec_helper'

describe "Enumerable#collect" do
  it "is an alias of Enumerable#map" do
    Enumerable.instance_method(:collect).should == Enumerable.instance_method(:map)
  end
end
