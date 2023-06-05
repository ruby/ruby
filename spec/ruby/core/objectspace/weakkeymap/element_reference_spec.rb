require_relative '../../../spec_helper'

ruby_version_is "3.3" do
  describe "ObjectSpace::WeakKeyMap#[]" do
    it "is faithful to the map's content" do
      map = ObjectSpace::WeakKeyMap.new
      key1, key2 = %w[a b].map(&:upcase)
      ref1, ref2 = %w[x y]
      map[key1] = ref1
      map[key1].should == ref1
      map[key1] = ref1
      map[key1].should == ref1
      map[key2] = ref2
      map[key1].should == ref1
      map[key2].should == ref2
    end

    it "matches using equality semantics" do
      map = ObjectSpace::WeakKeyMap.new
      key1, key2 = %w[a a].map(&:upcase)
      ref = "x"
      map[key1] = ref
      map[key2].should == ref
    end
  end
end
