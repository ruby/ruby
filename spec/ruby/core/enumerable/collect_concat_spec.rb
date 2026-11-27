require_relative '../../spec_helper'

describe "Enumerable#collect_concat" do
  it "is an alias of Enumerable#flat_map" do
    Enumerable.instance_method(:collect_concat).should == Enumerable.instance_method(:flat_map)
  end
end
