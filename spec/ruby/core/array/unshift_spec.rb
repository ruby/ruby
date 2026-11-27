require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Array#unshift" do
  it "prepends object to the original array" do
    a = [1, 2, 3]
    a.unshift("a").should.equal?(a)
    a.should == ['a', 1, 2, 3]
    a.unshift.should.equal?(a)
    a.should == ['a', 1, 2, 3]
    a.unshift(5, 4, 3)
    a.should == [5, 4, 3, 'a', 1, 2, 3]

    # shift all but one element
    a = [1, 2]
    a.shift
    a.unshift(3, 4)
    a.should == [3, 4, 2]

    # now shift all elements
    a.shift
    a.shift
    a.shift
    a.unshift(3, 4)
    a.should == [3, 4]
  end

  it "returns self" do
    a = [1, 2, 3]
    a.unshift("a").should.equal?(a)
  end

  it "quietly ignores unshifting nothing" do
    [].unshift.should == []
  end

  it "properly handles recursive arrays" do
    empty = ArraySpecs.empty_recursive_array
    empty.unshift(:new).should == [:new, empty]

    array = ArraySpecs.recursive_array
    array.unshift(:new)
    array[0..5].should == [:new, 1, 'two', 3.0, array, array]
  end

  it "raises a FrozenError on a frozen array when the array is modified" do
    -> { ArraySpecs.frozen_array.unshift(1) }.should.raise(FrozenError)
  end

  # see [ruby-core:23666]
  it "raises a FrozenError on a frozen array when the array would not be modified" do
    -> { ArraySpecs.frozen_array.unshift }.should.raise(FrozenError)
  end

  # https://github.com/truffleruby/truffleruby/issues/2772
  it "doesn't rely on Array#[]= so it can be overridden" do
    subclass = Class.new(Array) do
      def []=(*)
        raise "[]= is called"
      end
    end

    array = subclass.new
    array.unshift(1)
    array.should == [1]
  end
end
