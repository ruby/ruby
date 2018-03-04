require_relative '../../../spec_helper'
require 'set'

describe "SortedSet[]" do
  it "returns a new SortedSet populated with the passed Objects" do
    set = SortedSet[1, 2, 3]

    set.instance_of?(SortedSet).should be_true
    set.size.should eql(3)

    set.should include(1)
    set.should include(2)
    set.should include(3)
  end
end
