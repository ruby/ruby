require_relative '../../../spec_helper'

ruby_version_is ""..."3.0" do
  require 'set'

  describe "SortedSet#^" do
    before :each do
      @set = SortedSet[1, 2, 3, 4]
    end

    it "returns a new SortedSet containing elements that are not in both self and the passed Enumerable" do
      (@set ^ SortedSet[3, 4, 5]).should == SortedSet[1, 2, 5]
      (@set ^ [3, 4, 5]).should == SortedSet[1, 2, 5]
    end

    it "raises an ArgumentError when passed a non-Enumerable" do
      -> { @set ^ 3 }.should raise_error(ArgumentError)
      -> { @set ^ Object.new }.should raise_error(ArgumentError)
    end
  end
end
