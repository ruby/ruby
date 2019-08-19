require_relative '../../spec_helper'

describe "Array#count" do
  it "returns the number of elements" do
    [:a, :b, :c].count.should == 3
  end

  it "returns the number of elements that equal the argument" do
    [:a, :b, :b, :c].count(:b).should == 2
  end

  it "returns the number of element for which the block evaluates to true" do
    [:a, :b, :c].count { |s| s != :b }.should == 2
  end
end
