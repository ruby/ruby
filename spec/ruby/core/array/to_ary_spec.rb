require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Array#to_ary" do
  it "returns self" do
    a = [1, 2, 3]
    a.should equal(a.to_ary)
    a = ArraySpecs::MyArray[1, 2, 3]
    a.should equal(a.to_ary)
  end

  it "properly handles recursive arrays" do
    empty = ArraySpecs.empty_recursive_array
    empty.to_ary.should == empty

    array = ArraySpecs.recursive_array
    array.to_ary.should == array
  end

end
