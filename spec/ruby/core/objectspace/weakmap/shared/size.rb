describe :weakmap_size, shared: true do
  it "is correct" do
    map = ObjectSpace::WeakMap.new
    key1, key2 = %w[a b].map(&:upcase)
    ref1, ref2 = %w[x y]
    map.send(@method).should == 0
    map[key1] = ref1
    map.send(@method).should == 1
    map[key1] = ref1
    map.send(@method).should == 1
    map[key2] = ref2
    map.send(@method).should == 2
  end
end
