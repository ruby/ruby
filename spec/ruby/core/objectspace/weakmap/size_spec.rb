require_relative '../../../spec_helper'

describe "ObjectSpace::WeakMap#size" do
  it "is correct" do
    map = ObjectSpace::WeakMap.new
    key1, key2 = %w[a b].map(&:upcase)
    ref1, ref2 = %w[x y]
    map.size.should == 0
    map[key1] = ref1
    map.size.should == 1
    map[key1] = ref1
    map.size.should == 1
    map[key2] = ref2
    map.size.should == 2
  end
end
