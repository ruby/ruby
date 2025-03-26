require_relative '../../../spec_helper'

ruby_version_is "3.3" do
  describe "ObjectSpace::WeakKeyMap#[]=" do
    def should_accept(map, key, value)
      (map[key] = value).should == value
      map.should.key?(key)
      map[key].should == value
    end

    it "is correct" do
      map = ObjectSpace::WeakKeyMap.new
      key1, key2 = %w[a b].map(&:upcase)
      ref1, ref2 = %w[x y]
      should_accept(map, key1, ref1)
      should_accept(map, key1, ref1)
      should_accept(map, key2, ref2)
      map[key1].should == ref1
    end

    it "requires the keys to implement #hash" do
      map = ObjectSpace::WeakKeyMap.new
      -> { map[BasicObject.new] = 1 }.should raise_error(NoMethodError, /undefined method [`']hash' for an instance of BasicObject/)
    end

    it "accepts frozen keys or values" do
      map = ObjectSpace::WeakKeyMap.new
      x = Object.new
      should_accept(map, x, true)
      should_accept(map, x, false)
      should_accept(map, x, 42)
      should_accept(map, x, :foo)

      y = Object.new.freeze
      should_accept(map, x, y)
      should_accept(map, y, x)
    end

    it "does not duplicate and freeze String keys (like Hash#[]= does)" do
      map = ObjectSpace::WeakKeyMap.new
      key = +"a"
      map[key] = 1

      map.getkey("a").should.equal? key
      map.getkey("a").should_not.frozen?

      key.should == "a" # keep the key alive until here to keep the map entry
    end

    context "a key cannot be garbage collected" do
      it "raises ArgumentError when Integer is used as a key" do
        map = ObjectSpace::WeakKeyMap.new
        -> { map[1] = "x" }.should raise_error(ArgumentError, /WeakKeyMap (keys )?must be garbage collectable/)
      end

      it "raises ArgumentError when Float is used as a key" do
        map = ObjectSpace::WeakKeyMap.new
        -> { map[1.0] = "x" }.should raise_error(ArgumentError, /WeakKeyMap (keys )?must be garbage collectable/)
      end

      it "raises ArgumentError when Symbol is used as a key" do
        map = ObjectSpace::WeakKeyMap.new
        -> { map[:a] = "x" }.should raise_error(ArgumentError, /WeakKeyMap (keys )?must be garbage collectable/)
      end

      it "raises ArgumentError when true is used as a key" do
        map = ObjectSpace::WeakKeyMap.new
        -> { map[true] = "x" }.should raise_error(ArgumentError, /WeakKeyMap (keys )?must be garbage collectable/)
      end

      it "raises ArgumentError when false is used as a key" do
        map = ObjectSpace::WeakKeyMap.new
        -> { map[false] = "x" }.should raise_error(ArgumentError, /WeakKeyMap (keys )?must be garbage collectable/)
      end

      it "raises ArgumentError when nil is used as a key" do
        map = ObjectSpace::WeakKeyMap.new
        -> { map[nil] = "x" }.should raise_error(ArgumentError, /WeakKeyMap (keys )?must be garbage collectable/)
      end
    end
  end
end
