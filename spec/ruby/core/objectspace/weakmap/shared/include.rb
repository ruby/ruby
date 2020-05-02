describe :weakmap_include?, shared: true do
  it "recognizes keys in use" do
    map = ObjectSpace::WeakMap.new
    key1, key2 = %w[a b].map(&:upcase)
    ref1, ref2 = %w[x y]

    map[key1] = ref1
    map.send(@method, key1).should == true
    map[key1] = ref1
    map.send(@method, key1).should == true
    map[key2] = ref2
    map.send(@method, key2).should == true
  end

  it "matches using identity semantics" do
    map = ObjectSpace::WeakMap.new
    key1, key2 = %w[a a].map(&:upcase)
    ref = "x"
    map[key1] = ref
    map.send(@method, key2).should == false
  end

  ruby_version_is "2.7" do
    ruby_bug "#16826", "2.7.0"..."2.7.2" do
      it "reports true if the pair exists and the value is nil" do
        map = ObjectSpace::WeakMap.new
        key = Object.new
        map[key] = nil
        map.size.should == 1
        map.send(@method, key).should == true
      end
    end
  end
end
