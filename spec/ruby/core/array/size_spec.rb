require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Array#size" do
  it "returns the number of elements" do
    [].size.should == 0
    [1, 2, 3].size.should == 3
  end

  it "properly handles recursive arrays" do
    ArraySpecs.empty_recursive_array.size.should == 1
    ArraySpecs.recursive_array.size.should == 8
  end
end
