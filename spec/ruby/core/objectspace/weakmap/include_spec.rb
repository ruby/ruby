require_relative '../../../spec_helper'

describe "ObjectSpace::WeakMap#include?" do
  it "recognizes keys in use" do
    map = ObjectSpace::WeakMap.new
    key1, key2 = %w[a b].map(&:upcase)
    ref1, ref2 = %w[x y]

    map[key1] = ref1
    map.include?(key1).should == true
    map[key1] = ref1
    map.include?(key1).should == true
    map[key2] = ref2
    map.include?(key2).should == true
  end

  it "matches using identity semantics" do
    map = ObjectSpace::WeakMap.new
    key1, key2 = %w[a a].map(&:upcase)
    ref = "x"
    map[key1] = ref
    map.include?(key2).should == false
  end

  it "reports true if the pair exists and the value is nil" do
    map = ObjectSpace::WeakMap.new
    key = Object.new
    map[key] = nil
    map.size.should == 1
    map.include?(key).should == true
  end
end
