require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/enumeratorize'
require_relative 'shared/keep_if'
require_relative '../enumerable/shared/enumeratorized'

describe "Array#filter" do
  it_behaves_like :enumeratorize, :filter
  it_behaves_like :enumeratorized_with_origin_size, :filter, [1,2,3]

  it "returns a new array of elements for which block is true" do
    [1, 3, 4, 5, 6, 9].filter { |i| i % ((i + 1) / 2) == 0}.should == [1, 4, 6]
  end

  it "does not return subclass instance on Array subclasses" do
    ArraySpecs::MyArray[1, 2, 3].filter { true }.should be_an_instance_of(Array)
  end

  it "properly handles recursive arrays" do
    empty = ArraySpecs.empty_recursive_array
    empty.filter { true }.should == empty
    empty.filter { false }.should == []

    array = ArraySpecs.recursive_array
    array.filter { true }.should == [1, 'two', 3.0, array, array, array, array, array]
    array.filter { false }.should == []
  end
end

describe "Array#filter!" do
  it "returns nil if no changes were made in the array" do
    [1, 2, 3].filter! { true }.should be_nil
  end

  it_behaves_like :keep_if, :select!
end
