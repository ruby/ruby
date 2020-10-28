describe :weakmap_members, shared: true do
  it "is correct" do
    map = ObjectSpace::WeakMap.new
    key1, key2 = %w[a b].map(&:upcase)
    ref1, ref2 = %w[x y]
    @method.call(map).should == []
    map[key1] = ref1
    @method.call(map).should == @object[0..0]
    map[key1] = ref1
    @method.call(map).should == @object[0..0]
    map[key2] = ref2
    @method.call(map).sort.should == @object
  end
end
