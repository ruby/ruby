require_relative '../../../spec_helper'

ruby_version_is "3.3" do
  describe "ObjectSpace::WeakKeyMap#getkey" do
    it "returns the existing equal key" do
      map = ObjectSpace::WeakKeyMap.new
      key1, key2 = %w[a a].map(&:upcase)

      map[key1] = true
      map.getkey(key2).should equal(key1)
      map.getkey("X").should == nil

      key1.should == "A" # keep the key alive until here to keep the map entry
      key2.should == "A" # keep the key alive until here to keep the map entry
    end

    it "returns nil when a key cannot be garbage collected" do
      map = ObjectSpace::WeakKeyMap.new

      map.getkey(1).should == nil
      map.getkey(1.0).should == nil
      map.getkey(:a).should == nil
      map.getkey(true).should == nil
      map.getkey(false).should == nil
      map.getkey(nil).should == nil
    end
  end
end
