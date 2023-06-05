require_relative '../../../spec_helper'

ruby_version_is "3.3" do
  describe "ObjectSpace::WeakKeyMap#[]=" do
    def should_accept(map, key, value)
      (map[key] = value).should == value
      map.should.key?(key)
      map[key].should == value
    end

    def should_not_accept(map, key, value)
      -> { map[key] = value }.should raise_error(ArgumentError)
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
      -> { map[BasicObject.new] = 1 }.should raise_error(NoMethodError, "undefined method `hash' for an instance of BasicObject")
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

    it "rejects symbols as keys" do
      map = ObjectSpace::WeakKeyMap.new
      should_not_accept(map, :foo, true)
      should_not_accept(map, rand.to_s.to_sym, true)
    end

    it "rejects integers as keys" do
      map = ObjectSpace::WeakKeyMap.new
      should_not_accept(map, 42, true)
      should_not_accept(map, 2 ** 68, true)
    end

    it "rejects floats as keys" do
      map = ObjectSpace::WeakKeyMap.new
      should_not_accept(map, 4.2, true)
    end

    it "rejects booleans as keys" do
      map = ObjectSpace::WeakKeyMap.new
      should_not_accept(map, true, true)
      should_not_accept(map, false, true)
    end

    it "rejects nil as keys" do
      map = ObjectSpace::WeakKeyMap.new
      should_not_accept(map, nil, true)
    end
  end
end
