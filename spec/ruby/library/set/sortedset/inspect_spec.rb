require_relative '../../../spec_helper'

ruby_version_is ""..."3.0" do
  require 'set'

  describe "SortedSet#inspect" do
    it "returns a String representation of self" do
      SortedSet[].inspect.should be_kind_of(String)
      SortedSet[1, 2, 3].inspect.should be_kind_of(String)
      SortedSet["1", "2", "3"].inspect.should be_kind_of(String)
    end
  end
end
