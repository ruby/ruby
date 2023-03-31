require_relative '../../../spec_helper'

describe "ObjectSpace::WeakMap#getkey" do
  it "returns the existing equal key" do
    map = ObjectSpace::WeakKeyMap.new
    key1, key2 = %w[a a].map(&:upcase)

    map[key1] = true
    map.getkey(key2).should equal(key1)
    map.getkey("X").should == nil
  end
end
