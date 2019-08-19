# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerator::Lazy#chunk" do

  before :each do
    @yieldsmixed = EnumeratorLazySpecs::YieldsMixed.new.to_enum.lazy
    @eventsmixed = EnumeratorLazySpecs::EventsMixed.new.to_enum.lazy
    ScratchPad.record []
  end

  after :each do
    ScratchPad.clear
  end

  it "returns a new instance of Enumerator::Lazy" do
    ret = @yieldsmixed.chunk {}
    ret.should be_an_instance_of(Enumerator::Lazy)
    ret.should_not equal(@yieldsmixed)
  end

  it "sets #size to nil" do
    Enumerator::Lazy.new(Object.new, 100) {}.chunk { |v| v }.size.should == nil
  end

  it "returns an Enumerator if called without a block" do
    chunk = @yieldsmixed.chunk
    chunk.should be_an_instance_of(Enumerator::Lazy)

    res = chunk.each { |v| true }.force
    res.should == [[true, EnumeratorLazySpecs::YieldsMixed.gathered_yields]]
  end

  describe "when the returned lazy enumerator is evaluated by Enumerable#first" do
    it "stops after specified times" do
      first_two = (0..Float::INFINITY).lazy.chunk { |n| n.even? }.first(2)
      first_two.should == [[true, [0]], [false, [1]]]
    end
  end

  it "calls the block with gathered values when yield with multiple arguments" do
    yields = []
    @yieldsmixed.chunk { |v| yields << v; true }.force
    yields.should == EnumeratorLazySpecs::YieldsMixed.gathered_yields
  end

  describe "on a nested Lazy" do
    it "sets #size to nil" do
      Enumerator::Lazy.new(Object.new, 100) {}.take(20).chunk { |v| v }.size.should == nil
    end

    describe "when the returned lazy enumerator is evaluated by Enumerable#first" do
      it "stops after specified times" do
        remains_lazy = (0..Float::INFINITY).lazy.chunk { |n| n }
        remains_lazy.chunk { |n| n }.first(2).size.should == 2
      end
    end
  end

  it "works with an infinite enumerable" do
    s = 0..Float::INFINITY
    s.lazy.chunk { |n| n.even? }.first(100).should ==
      s.first(100).chunk { |n| n.even? }.to_a
  end
end
