require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/difference'

describe "Array#difference" do
  it_behaves_like :array_binary_difference, :difference

  it "returns a copy when called without any parameter" do
    x = [1, 2, 3, 2]
    x.difference.should == x
    x.difference.should_not equal x
  end

  it "does not return subclass instances for Array subclasses" do
    ArraySpecs::MyArray[1, 2, 3].difference.should be_an_instance_of(Array)
  end

  it "accepts multiple arguments" do
    x = [1, 2, 3, 1]
    x.difference([], [0, 1], [3, 4], [3]).should == [2]
  end
end
