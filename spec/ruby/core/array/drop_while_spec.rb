require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Array#drop_while" do
  it "removes elements from the start of the array while the block evaluates to true" do
    [1, 2, 3, 4].drop_while { |n| n < 4 }.should == [4]
  end

  it "removes elements from the start of the array until the block returns nil" do
    [1, 2, 3, nil, 5].drop_while { |n| n }.should == [nil, 5]
  end

  it "removes elements from the start of the array until the block returns false" do
    [1, 2, 3, false, 5].drop_while { |n| n }.should == [false, 5]
  end

  ruby_version_is ''...'3.0' do
    it 'returns a subclass instance for Array subclasses' do
      ArraySpecs::MyArray[1, 2, 3, 4, 5].drop_while { |n| n < 4 }.should be_an_instance_of(ArraySpecs::MyArray)
    end
  end

  ruby_version_is '3.0' do
    it 'returns a Array instance for Array subclasses' do
      ArraySpecs::MyArray[1, 2, 3, 4, 5].drop_while { |n| n < 4 }.should be_an_instance_of(Array)
    end
  end
end
