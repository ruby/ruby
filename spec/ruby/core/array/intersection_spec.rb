require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Array#intersect" do
  it "creates an array with elements common to both arrays (intersection)" do
    [].intersection([]).should == []
    [1, 2].intersection([]).should == []
    [].intersection([1, 2]).should == []
    [ 1, 3, 5 ].intersection([ 1, 2, 3 ]).should == [1, 3]
  end

  it "creates an array with no duplicates" do
    [ 1, 1, 3, 5 ].intersection([ 1, 2, 3 ]).uniq!.should == nil
  end

  it "creates an array with elements in order they are first encountered" do
    [ 1, 2, 3, 2, 5 ].intersection([ 5, 2, 3, 4 ]).should == [2, 3, 5]
  end

  it "does not modify the original Array" do
    a = [1, 1, 3, 5]
    a.intersection([1, 2, 3]).should == [1, 3]
    a.should == [1, 1, 3, 5]
  end

  it "properly handles recursive arrays" do
    empty = ArraySpecs.empty_recursive_array
    empty.intersection(empty).should == empty

    ArraySpecs.recursive_array.intersection([]).should == []
    [].intersection(ArraySpecs.recursive_array).should == []

    ArraySpecs.recursive_array.intersection(ArraySpecs.recursive_array).should == [1, 'two', 3.0, ArraySpecs.recursive_array]
  end

  it "tries to convert the passed argument to an Array using #to_ary" do
    obj = mock('[1,2,3]')
    obj.should_receive(:to_ary).and_return([1, 2, 3])
    [1, 2].intersection(obj).should == ([1, 2])
  end

  it "determines equivalence between elements in the sense of eql?" do
    not_supported_on :opal do
      [5.0, 4.0].intersection([5, 4]).should == []
    end

    str = "x"
    [str].intersection([str.dup]).should == [str]

    obj1 = mock('1')
    obj2 = mock('2')
    obj1.stub!(:hash).and_return(0)
    obj2.stub!(:hash).and_return(0)
    obj1.should_receive(:eql?).at_least(1).and_return(true)
    obj2.stub!(:eql?).and_return(true)

    [obj1].intersection([obj2]).should == [obj1]
    [obj1, obj1, obj2, obj2].intersection([obj2]).should == [obj1]

    obj1 = mock('3')
    obj2 = mock('4')
    obj1.stub!(:hash).and_return(0)
    obj2.stub!(:hash).and_return(0)
    obj1.should_receive(:eql?).at_least(1).and_return(false)

    [obj1].intersection([obj2]).should == []
    [obj1, obj1, obj2, obj2].intersection([obj2]).should == [obj2]
  end

  it "does return subclass instances for Array subclasses" do
    ArraySpecs::MyArray[1, 2, 3].intersection([]).should be_an_instance_of(Array)
    ArraySpecs::MyArray[1, 2, 3].intersection(ArraySpecs::MyArray[1, 2, 3]).should be_an_instance_of(Array)
    [].intersection(ArraySpecs::MyArray[1, 2, 3]).should be_an_instance_of(Array)
  end

  it "does not call to_ary on array subclasses" do
    [5, 6].intersection(ArraySpecs::ToAryArray[1, 2, 5, 6]).should == [5, 6]
  end

  it "properly handles an identical item even when its #eql? isn't reflexive" do
    x = mock('x')
    x.stub!(:hash).and_return(42)
    x.stub!(:eql?).and_return(false) # Stubbed for clarity and latitude in implementation; not actually sent by MRI.

    [x].intersection([x]).should == [x]
  end
end
