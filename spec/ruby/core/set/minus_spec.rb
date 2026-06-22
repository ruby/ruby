require_relative '../../spec_helper'

describe "Set#-" do
  before :each do
    @set = Set[:a, :b, :c]
  end

  it "returns a new Set containing self's elements excluding the elements in the passed Enumerable" do
    (@set - Set[:a, :b]).should == Set[:c]
    (@set - [:b, :c]).should == Set[:a]
  end

  it "raises an ArgumentError when passed a non-Enumerable" do
    -> { @set - 1 }.should.raise(ArgumentError)
    -> { @set - Object.new }.should.raise(ArgumentError)
  end
end
