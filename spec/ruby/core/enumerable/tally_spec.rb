require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerable#tally" do
  before :each do
    ScratchPad.record []
  end

  it "returns a hash with counts according to the value" do
    enum = EnumerableSpecs::Numerous.new('foo', 'bar', 'foo', 'baz')
    enum.tally.should == { 'foo' => 2, 'bar' => 1, 'baz' => 1}
  end

  it "returns a hash without default" do
    hash = EnumerableSpecs::Numerous.new('foo', 'bar', 'foo', 'baz').tally
    hash.default_proc.should be_nil
    hash.default.should be_nil
  end

  it "returns an empty hash for empty enumerables" do
    EnumerableSpecs::Empty.new.tally.should == {}
  end

  it "counts values as gathered array when yielded with multiple arguments" do
    EnumerableSpecs::YieldsMixed2.new.tally.should == EnumerableSpecs::YieldsMixed2.gathered_yields.group_by(&:itself).transform_values(&:size)
  end

  it "does not call given block" do
    enum = EnumerableSpecs::Numerous.new('foo', 'bar', 'foo', 'baz')
    enum.tally { |v| ScratchPad << v }
    ScratchPad.recorded.should == []
  end
end

ruby_version_is "3.1" do
  describe "Enumerable#tally with a hash" do
    before :each do
      ScratchPad.record []
    end

    it "returns a hash with counts according to the value" do
      enum = EnumerableSpecs::Numerous.new('foo', 'bar', 'foo', 'baz')
      enum.tally({ 'foo' => 1 }).should == { 'foo' => 3, 'bar' => 1, 'baz' => 1}
    end

    it "returns the given hash" do
      enum = EnumerableSpecs::Numerous.new('foo', 'bar', 'foo', 'baz')
      hash = { 'foo' => 1 }
      enum.tally(hash).should equal(hash)
    end

    it "raises a FrozenError and does not update the given hash when the hash is frozen" do
      enum = EnumerableSpecs::Numerous.new('foo', 'bar', 'foo', 'baz')
      hash = { 'foo' => 1 }.freeze
      -> { enum.tally(hash) }.should raise_error(FrozenError)
      hash.should == { 'foo' => 1 }
    end

    it "does not call given block" do
      enum = EnumerableSpecs::Numerous.new('foo', 'bar', 'foo', 'baz')
      enum.tally({ 'foo' => 1 }) { |v| ScratchPad << v }
      ScratchPad.recorded.should == []
    end

    it "ignores the default value" do
      enum = EnumerableSpecs::Numerous.new('foo', 'bar', 'foo', 'baz')
      enum.tally(Hash.new(100)).should == { 'foo' => 2, 'bar' => 1, 'baz' => 1}
    end

    it "ignores the default proc" do
      enum = EnumerableSpecs::Numerous.new('foo', 'bar', 'foo', 'baz')
      enum.tally(Hash.new {100}).should == { 'foo' => 2, 'bar' => 1, 'baz' => 1}
    end

    it "needs the values counting each elements to be an integer" do
      enum = EnumerableSpecs::Numerous.new('foo')
      -> { enum.tally({ 'foo' => 'bar' }) }.should raise_error(TypeError)
    end
  end
end
