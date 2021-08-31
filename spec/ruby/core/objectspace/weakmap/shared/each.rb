describe :weakmap_each, shared: true do
  it "must take a block, except when empty" do
    map = ObjectSpace::WeakMap.new
    key = "a".upcase
    ref = "x"
    map.send(@method).should == map
    map[key] = ref
    -> { map.send(@method) }.should raise_error(LocalJumpError)
  end
end
