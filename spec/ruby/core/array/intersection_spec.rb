require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/intersection'

describe "Array#&" do
  it_behaves_like :array_intersection, :&
end

describe "Array#intersection" do
  it_behaves_like :array_intersection, :intersection

  it "accepts multiple arguments" do
    [1, 2, 3, 4].intersection([1, 2, 3], [2, 3, 4]).should == [2, 3]
  end

  it "preserves elements order from original array" do
    [1, 2, 3, 4].intersection([3, 2, 1]).should == [1, 2, 3]
  end
end
