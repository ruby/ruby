require_relative '../../spec_helper'
require_relative 'shared/iterable_and_tolerating_size_increasing'

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

  it "ignores the block if there is an argument" do
    -> {
      [:a, :b, :b, :c].count(:b) { |e| e.size > 10 }.should == 2
    }.should complain(/given block not used/)
  end

  context "when a block argument given" do
    it_behaves_like :array_iterable_and_tolerating_size_increasing, :count
  end
end
