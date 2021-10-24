require_relative '../../../spec_helper'

ruby_version_is ""..."3.0" do
  require 'set'

  describe "SortedSet#clear" do
    before :each do
      @set = SortedSet["one", "two", "three", "four"]
    end

    it "removes all elements from self" do
      @set.clear
      @set.should be_empty
    end

    it "returns self" do
      @set.clear.should equal(@set)
    end
  end
end
