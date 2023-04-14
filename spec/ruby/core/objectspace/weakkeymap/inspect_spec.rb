require_relative '../../../spec_helper'

ruby_version_is "3.3" do
  describe "ObjectSpace::WeakKeyMap#inspect" do
    it "only displays size in output" do
      map = ObjectSpace::WeakKeyMap.new
      key1, key2, key3 = "foo", "bar", "bar"
      map.inspect.should =~ /\A\#<ObjectSpace::WeakKeyMap:0x\h+ size=0>\z/
      map[key1] = 1
      map.inspect.should =~ /\A\#<ObjectSpace::WeakKeyMap:0x\h+ size=1>\z/
      map[key2] = 2
      map.inspect.should =~ /\A\#<ObjectSpace::WeakKeyMap:0x\h+ size=2>\z/
      map[key3] = 3
      map.inspect.should =~ /\A\#<ObjectSpace::WeakKeyMap:0x\h+ size=2>\z/
    end
  end
end
