require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Array#+" do
  it "concatenates two arrays" do
    ([ 1, 2, 3 ] + [ 3, 4, 5 ]).should == [1, 2, 3, 3, 4, 5]
    ([ 1, 2, 3 ] + []).should == [1, 2, 3]
    ([] + [ 1, 2, 3 ]).should == [1, 2, 3]
    ([] + []).should == []
  end

  it "can concatenate an array with itself" do
    ary = [1, 2, 3]
    (ary + ary).should == [1, 2, 3, 1, 2, 3]
  end

  describe "converts the passed argument to an Array using #to_ary" do
    it "successfully concatenates the resulting array from the #to_ary call" do
      obj = mock('["x", "y"]')
      obj.should_receive(:to_ary).and_return(["x", "y"])
      ([1, 2, 3] + obj).should == [1, 2, 3, "x", "y"]
    end

    it "raises a TypeError if the given argument can't be converted to an array" do
      -> { [1, 2, 3] + nil }.should raise_error(TypeError)
      -> { [1, 2, 3] + "abc" }.should raise_error(TypeError)
    end

    it "raises a NoMethodError if the given argument raises a NoMethodError during type coercion to an Array" do
      obj = mock("hello")
      obj.should_receive(:to_ary).and_raise(NoMethodError)
      -> { [1, 2, 3] + obj }.should raise_error(NoMethodError)
    end
  end

  it "properly handles recursive arrays" do
    empty = ArraySpecs.empty_recursive_array
    (empty + empty).should == [empty, empty]

    array = ArraySpecs.recursive_array
    (empty + array).should == [empty, 1, 'two', 3.0, array, array, array, array, array]
    (array + array).should == [
      1, 'two', 3.0, array, array, array, array, array,
      1, 'two', 3.0, array, array, array, array, array]
  end

  it "does return subclass instances with Array subclasses" do
    (ArraySpecs::MyArray[1, 2, 3] + []).should be_an_instance_of(Array)
    (ArraySpecs::MyArray[1, 2, 3] + ArraySpecs::MyArray[]).should be_an_instance_of(Array)
    ([1, 2, 3] + ArraySpecs::MyArray[]).should be_an_instance_of(Array)
  end

  it "does not call to_ary on array subclasses" do
    ([5, 6] + ArraySpecs::ToAryArray[1, 2]).should == [5, 6, 1, 2]
  end
end
