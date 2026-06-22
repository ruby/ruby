require_relative '../../spec_helper'

describe "Set#union" do
  it "is an alias of Set#|" do
    Set.instance_method(:union).should == Set.instance_method(:|)
  end
end

describe "Set#|" do
  before :each do
    @set = Set[:a, :b, :c]
  end

  it "returns a new Set containing all elements of self and the passed Enumerable" do
    (@set | Set[:b, :d, :e]).should == Set[:a, :b, :c, :d, :e]
    (@set | [:b, :e]).should == Set[:a, :b, :c, :e]
  end

  it "raises an ArgumentError when passed a non-Enumerable" do
    -> { @set | 1 }.should.raise(ArgumentError)
    -> { @set | Object.new }.should.raise(ArgumentError)
  end
end
