require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Array#length" do
  it "returns the number of elements" do
    [].length.should == 0
    [1, 2, 3].length.should == 3
  end

  it "properly handles recursive arrays" do
    ArraySpecs.empty_recursive_array.length.should == 1
    ArraySpecs.recursive_array.length.should == 8
  end
end
