require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Array#take_while" do
  it "returns all elements until the block returns false" do
    [1, 2, 3].take_while{ |element| element < 3 }.should == [1, 2]
  end

  it "returns all elements until the block returns nil" do
    [1, 2, nil, 4].take_while{ |element| element }.should == [1, 2]
  end

  it "returns all elements until the block returns false" do
    [1, 2, false, 4].take_while{ |element| element }.should == [1, 2]
  end

  ruby_version_is ''...'3.0' do
    it 'returns a subclass instance for Array subclasses' do
      ArraySpecs::MyArray[1, 2, 3, 4, 5].take_while { |n| n < 4 }.should be_an_instance_of(ArraySpecs::MyArray)
    end
  end

  ruby_version_is '3.0' do
    it 'returns a Array instance for Array subclasses' do
      ArraySpecs::MyArray[1, 2, 3, 4, 5].take_while { |n| n < 4 }.should be_an_instance_of(Array)
    end
  end
end
