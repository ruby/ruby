require_relative '../../spec_helper'

describe "Set#intersection" do
  it "is an alias of Set#&" do
    Set.instance_method(:intersection).should == Set.instance_method(:&)
  end
end

describe "Set#&" do
  before :each do
    @set = Set[:a, :b, :c]
  end

  it "returns a new Set containing only elements shared by self and the passed Enumerable" do
    (@set & Set[:b, :c, :d, :e]).should == Set[:b, :c]
    (@set & [:b, :c, :d]).should == Set[:b, :c]
  end

  it "raises an ArgumentError when passed a non-Enumerable" do
    -> { @set & 1 }.should.raise(ArgumentError)
    -> { @set & Object.new }.should.raise(ArgumentError)
  end

  it "does not retain compare_by_identity flag" do
    @set.compare_by_identity
    (@set & Set[:b, :c, :d, :e]).compare_by_identity?.should == false
    (@set & [:b, :c, :d]).compare_by_identity?.should == false
  end
end
