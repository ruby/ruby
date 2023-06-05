require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/enumeratorize'
require_relative 'shared/iterable_and_tolerating_size_increasing'
require_relative '../enumerable/shared/enumeratorized'

# Mutating the array while it is being iterated is discouraged as it can result in confusing behavior.
# Yet a Ruby implementation must not crash in such a case, and following the simple CRuby behavior makes sense.
# CRuby simply reads the array storage and checks the size for every iteration;
# like `i = 0; while i < size; yield self[i]; end`

describe "Array#each" do
  it "yields each element to the block" do
    a = []
    x = [1, 2, 3]
    x.each { |item| a << item }.should equal(x)
    a.should == [1, 2, 3]
  end

  it "yields each element to the block even if the array is changed during iteration" do
    a = [1, 2, 3, 4, 5]
    iterated = []
    a.each { |x| iterated << x; a << x+5 if x.even? }
    iterated.should == [1, 2, 3, 4, 5, 7, 9]
  end

  it "yields only elements that are still in the array" do
    a = [0, 1, 2, 3, 4]
    iterated = []
    a.each { |x| iterated << x; a.pop if x.even? }
    iterated.should == [0, 1, 2]
  end

  it "yields elements based on an internal index" do
    a = [0, 1, 2, 3, 4]
    iterated = []
    a.each { |x| iterated << x; a.shift if x.even? }
    iterated.should == [0, 2, 4]
  end

  it "yields the same element multiple times if inserting while iterating" do
    a = [1, 2]
    iterated = []
    a.each { |x| iterated << x; a.unshift(0) if a.size == 2 }
    iterated.should == [1, 1, 2]
  end

  it "yields each element to a block that takes multiple arguments" do
    a = [[1, 2], :a, [3, 4]]
    b = []

    a.each { |x, y| b << x }
    b.should == [1, :a, 3]

    b = []
    a.each { |x, y| b << y }
    b.should == [2, nil, 4]
  end

  it "yields elements added to the end of the array by the block" do
    a = [2]
    iterated = []
    a.each { |x| iterated << x; x.times { a << 0 } }

    iterated.should == [2, 0, 0]
  end

  it "does not yield elements deleted from the end of the array" do
    a = [2, 3, 1]
    iterated = []
    a.each { |x| iterated << x; a.delete_at(2) if x == 3 }

    iterated.should == [2, 3]
  end

  it_behaves_like :enumeratorize, :each
  it_behaves_like :enumeratorized_with_origin_size, :each, [1,2,3]
end

describe "Array#each" do
  it_behaves_like :array_iterable_and_tolerating_size_increasing, :each
end
