require_relative '../../spec_helper'

describe "Set#size" do
  it "returns the number of elements in the set" do
    set = Set[:a, :b, :c]
    set.size.should == 3
  end
end
