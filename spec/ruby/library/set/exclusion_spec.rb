require_relative '../../spec_helper'
require 'set'

describe "Set#^" do
  before :each do
    @set = Set[1, 2, 3, 4]
  end

  it "returns a new Set containing elements that are not in both self and the passed Enumerable" do
    (@set ^ Set[3, 4, 5]).should == Set[1, 2, 5]
    (@set ^ [3, 4, 5]).should == Set[1, 2, 5]
  end

  it "raises an ArgumentError when passed a non-Enumerable" do
    -> { @set ^ 3 }.should raise_error(ArgumentError)
    -> { @set ^ Object.new }.should raise_error(ArgumentError)
  end
end
