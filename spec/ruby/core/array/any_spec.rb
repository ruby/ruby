require_relative '../../spec_helper'
require_relative 'shared/iterable_and_tolerating_size_increasing'

describe "Array#any?" do
  describe 'with no block given (a default block of { |x| x } is implicit)' do
    it "is false if the array is empty" do
      empty_array = []
      empty_array.should_not.any?
    end

    it "is false if the array is not empty, but all the members of the array are falsy" do
      falsy_array = [false, nil, false]
      falsy_array.should_not.any?
    end

    it "is true if the array has any truthy members" do
      not_empty_array = ['anything', nil]
      not_empty_array.should.any?
    end
  end

  describe 'with a block given' do
    @value_to_return = -> _ { false }
    it_behaves_like :array_iterable_and_tolerating_size_increasing, :any?

    it 'is false if the array is empty' do
      empty_array = []
      empty_array.any? {|v| 1 == 1 }.should == false
    end

    it 'is true if the block returns true for any member of the array' do
      array_with_members = [false, false, true, false]
      array_with_members.any? {|v| v == true }.should == true
    end

    it 'is false if the block returns false for all members of the array' do
      array_with_members = [false, false, true, false]
      array_with_members.any? {|v| v == 42 }.should == false
    end
  end

  describe 'when given a pattern argument' do
    it "ignores the block if there is an argument" do
      -> {
        ['bar', 'foobar'].any?(/bar/) { false }.should == true
      }.should complain(/given block not used/)
    end
  end
end
