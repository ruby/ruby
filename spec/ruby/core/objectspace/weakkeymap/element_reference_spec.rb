require_relative '../../../spec_helper'
require_relative 'fixtures/classes'

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

    it "compares keys with #eql? semantics" do
      map = ObjectSpace::WeakKeyMap.new
      key = [1.0]
      map[key] = "x"
      map[[1]].should == nil
      map[[1.0]].should == "x"
      key.should == [1.0] # keep the key alive until here to keep the map entry

      map = ObjectSpace::WeakKeyMap.new
      key = [1]
      map[key] = "x"
      map[[1.0]].should == nil
      map[[1]].should == "x"
      key.should == [1] # keep the key alive until here to keep the map entry

      map = ObjectSpace::WeakKeyMap.new
      key1, key2 = %w[a a].map(&:upcase)
      ref = "x"
      map[key1] = ref
      map[key2].should == ref
    end

    it "compares key via #hash first" do
      x = mock('0')
      x.should_receive(:hash).and_return(0)

      map = ObjectSpace::WeakKeyMap.new
      key = 'foo'
      map[key] = :bar
      map[x].should == nil
    end

    it "does not compare keys with different #hash values via #eql?" do
      x = mock('x')
      x.should_not_receive(:eql?)
      x.stub!(:hash).and_return(0)

      y = mock('y')
      y.should_not_receive(:eql?)
      y.stub!(:hash).and_return(1)

      map = ObjectSpace::WeakKeyMap.new
      map[y] = 1
      map[x].should == nil
    end

    it "compares keys with the same #hash value via #eql?" do
      x = mock('x')
      x.should_receive(:eql?).and_return(true)
      x.stub!(:hash).and_return(42)

      y = mock('y')
      y.should_not_receive(:eql?)
      y.stub!(:hash).and_return(42)

      map = ObjectSpace::WeakKeyMap.new
      map[y] = 1
      map[x].should == 1
    end

    it "finds a value via an identical key even when its #eql? isn't reflexive" do
      x = mock('x')
      x.should_receive(:hash).at_least(1).and_return(42)
      x.stub!(:eql?).and_return(false) # Stubbed for clarity and latitude in implementation; not actually sent by MRI.

      map = ObjectSpace::WeakKeyMap.new
      map[x] = :x
      map[x].should == :x
    end

    it "supports keys with private #hash method" do
      key = WeakKeyMapSpecs::KeyWithPrivateHash.new
      map = ObjectSpace::WeakKeyMap.new
      map[key] = 42
      map[key].should == 42
    end

    it "returns nil and does not raise error when a key cannot be garbage collected" do
      map = ObjectSpace::WeakKeyMap.new

      map[1].should == nil
      map[1.0].should == nil
      map[:a].should == nil
      map[true].should == nil
      map[false].should == nil
      map[nil].should == nil
    end
  end
end
