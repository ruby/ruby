require_relative '../../spec_helper'
require_relative '../enumerable/shared/enumeratorized'
require_relative 'fixtures/classes'
require_relative 'shared/enumeratorize'
require_relative 'shared/iterable_and_tolerating_size_increasing'
require_relative 'shared/keep_if'

describe "Array#select" do
  it_behaves_like :enumeratorize, :select

  it_behaves_like :array_iterable_and_tolerating_size_increasing, :select

  before :each do
    @object = [1,2,3]
  end
  it_behaves_like :enumeratorized_with_origin_size, :select

  it "returns a new array of elements for which block is true" do
    [1, 3, 4, 5, 6, 9].select { |i| i % ((i + 1) / 2) == 0}.should == [1, 4, 6]
  end

  it "does not return subclass instance on Array subclasses" do
    ArraySpecs::MyArray[1, 2, 3].select { true }.should.instance_of?(Array)
  end

  it "properly handles recursive arrays" do
    empty = ArraySpecs.empty_recursive_array
    empty.select { true }.should == empty
    empty.select { false }.should == []

    array = ArraySpecs.recursive_array
    array.select { true }.should == [1, 'two', 3.0, array, array, array, array, array]
    array.select { false }.should == []
  end
end

describe "Array#select!" do
  it "returns nil if no changes were made in the array" do
    [1, 2, 3].select! { true }.should == nil
  end

  it_behaves_like :keep_if, :select!
end
