require_relative '../../../spec_helper'

ruby_version_is "3.3" do
  describe "ObjectSpace::WeakKeyMap#key?" do
    it "recognizes keys in use" do
      map = ObjectSpace::WeakKeyMap.new
      key1, key2 = %w[a b].map(&:upcase)
      ref1, ref2 = %w[x y]

      map[key1] = ref1
      map.key?(key1).should == true
      map[key1] = ref1
      map.key?(key1).should == true
      map[key2] = ref2
      map.key?(key2).should == true
    end

    it "matches using equality semantics" do
      map = ObjectSpace::WeakKeyMap.new
      key1, key2 = %w[a a].map(&:upcase)
      ref = "x"
      map[key1] = ref
      map.key?(key2).should == true
    end

    it "reports true if the pair exists and the value is nil" do
      map = ObjectSpace::WeakKeyMap.new
      key = Object.new
      map[key] = nil
      map.key?(key).should == true
    end
  end
end
