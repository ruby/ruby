require_relative '../../../spec_helper'
require 'set'

ruby_version_is "3.0" do
  describe "SortedSet" do
    it "raises error including message that it has been extracted from the set stdlib" do
      -> {
        SortedSet
      }.should raise_error(RuntimeError) { |e|
        e.message.should.include?("The `SortedSet` class has been extracted from the `set` library")
      }
    end
  end
end

ruby_version_is ""..."3.0" do
  describe "SortedSet" do
    it "is part of the set stdlib" do
      SortedSet.superclass.should == Set
    end
  end
end
