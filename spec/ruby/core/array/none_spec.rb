require_relative '../../spec_helper'

describe "Array#none?" do
  describe 'with no block given (a default block of { |x| x } is implicit)' do
    it "is true if the array is empty" do
      empty_array = []
      empty_array.should.none?
    end

    it "is true if the array is not empty, but all the members of the array are falsy" do
      falsy_array = [false, nil, false]
      falsy_array.should.none?
    end

    it "is false if the array has any truthy members" do
      not_empty_array = ['anything', nil]
      not_empty_array.should_not.none?
    end
  end

  describe 'with a block given' do
    it 'is false if the array is empty' do
      empty_array = []
      empty_array.none? {|element| 1 == 1 }.should == true
    end

    it 'is true if the block returns false for all members of the array' do
      array_with_members = [false, false, false]
      array_with_members.none? {|element| element == true }.should == true
    end

    it 'is false if the block returns true for any members of the array' do
      array_with_members = [false, false, true]
      array_with_members.none? {|element| element == true }.should == false
    end
  end
end
