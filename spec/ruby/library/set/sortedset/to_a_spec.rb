require_relative '../../../spec_helper'

ruby_version_is ""..."3.0" do
  require 'set'

  describe "SortedSet#to_a" do
    it "returns an array containing elements" do
      set = SortedSet.new [1, 2, 3]
      set.to_a.should == [1, 2, 3]
    end

    it "returns a sorted array containing elements" do
      set = SortedSet[2, 3, 1]
      set.to_a.should == [1, 2, 3]

      set = SortedSet.new [5, 6, 4, 4]
      set.to_a.should == [4, 5, 6]
    end
  end
end
