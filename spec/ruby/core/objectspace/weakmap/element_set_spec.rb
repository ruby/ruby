require_relative '../../../spec_helper'

describe "ObjectSpace::WeakMap#[]=" do
  def should_accept(map, key, value)
    (map[key] = value).should == value
    map.should.key?(key)
    map[key].should == value
  end

  it "is correct" do
    map = ObjectSpace::WeakMap.new
    key1, key2 = %w[a b].map(&:upcase)
    ref1, ref2 = %w[x y]
    should_accept(map, key1, ref1)
    should_accept(map, key1, ref1)
    should_accept(map, key2, ref2)
    map[key1].should == ref1
  end

  ruby_version_is ""..."2.7" do
    it "does not accept primitive or frozen keys or values" do
      map = ObjectSpace::WeakMap.new
      x = Object.new
      -> { map[true] = x }.should raise_error(ArgumentError)
      -> { map[false] = x }.should raise_error(ArgumentError)
      -> { map[nil] = x }.should raise_error(ArgumentError)
      -> { map[42] = x }.should raise_error(ArgumentError)
      -> { map[:foo] = x }.should raise_error(ArgumentError)
      -> { map[x] = true }.should raise_error(ArgumentError)
      -> { map[x] = false }.should raise_error(ArgumentError)
      -> { map[x] = nil }.should raise_error(ArgumentError)
      -> { map[x] = 42 }.should raise_error(ArgumentError)
      -> { map[x] = :foo }.should raise_error(ArgumentError)

      y = Object.new.freeze
      -> { map[x] = y}.should raise_error(FrozenError)
      -> { map[y] = x}.should raise_error(FrozenError)
    end
  end

  ruby_version_is "2.7" do
    it "accepts primitive or frozen keys or values" do
      map = ObjectSpace::WeakMap.new
      x = Object.new
      should_accept(map, true, x)
      should_accept(map, false, x)
      should_accept(map, nil, x)
      should_accept(map, 42, x)
      should_accept(map, :foo, x)

      should_accept(map, x, true)
      should_accept(map, x, false)
      should_accept(map, x, 42)
      should_accept(map, x, :foo)

      y = Object.new.freeze
      should_accept(map, x, y)
      should_accept(map, y, x)
    end
  end
end
