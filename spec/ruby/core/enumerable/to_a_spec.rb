require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerable#to_a" do
  it "returns an array containing the elements" do
    numerous = EnumerableSpecs::Numerous.new(1, nil, 'a', 2, false, true)
    numerous.to_a.should == [1, nil, "a", 2, false, true]
  end

  it "passes through the values yielded by #each_with_index" do
    [:a, :b].each_with_index.to_a.should == [[:a, 0], [:b, 1]]
  end

  it "passes arguments to each" do
    count = EnumerableSpecs::EachCounter.new(1, 2, 3)
    count.to_a(:hello, "world").should == [1, 2, 3]
    count.arguments_passed.should == [:hello, "world"]
  end
end
