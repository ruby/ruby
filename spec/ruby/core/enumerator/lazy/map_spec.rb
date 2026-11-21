require_relative '../../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerator::Lazy#map" do
  before :each do
    @yieldsmixed = EnumeratorLazySpecs::YieldsMixed.new.to_enum.lazy
    @eventsmixed = EnumeratorLazySpecs::EventsMixed.new.to_enum.lazy
    ScratchPad.record []
  end

  after :each do
    ScratchPad.clear
  end

  it "returns a new instance of Enumerator::Lazy" do
    ret = @yieldsmixed.map {}
    ret.should.instance_of?(Enumerator::Lazy)
    ret.should_not.equal?(@yieldsmixed)
  end

  it "keeps size" do
    Enumerator::Lazy.new(Object.new, 100) {}.map {}.size.should == 100
  end

  describe "when the returned lazy enumerator is evaluated by Enumerable#first" do
    it "stops after specified times" do
      (0..Float::INFINITY).lazy.map(&:succ).first(3).should == [1, 2, 3]

      @eventsmixed.map {}.first(1)
      ScratchPad.recorded.should == [:before_yield]
    end
  end

  it "calls the block with initial values when yield with multiple arguments" do
    yields = []
    @yieldsmixed.map { |v| yields << v }.force
    yields.should == EnumeratorLazySpecs::YieldsMixed.initial_yields
  end

  describe "on a nested Lazy" do
    it "keeps size" do
      Enumerator::Lazy.new(Object.new, 100) {}.map {}.map {}.size.should == 100
    end

    describe "when the returned lazy enumerator is evaluated by Enumerable#first" do
      it "stops after specified times" do
        (0..Float::INFINITY).lazy.map(&:succ).map(&:succ).first(3).should == [2, 3, 4]

        @eventsmixed.map {}.map {}.first(1)
        ScratchPad.recorded.should == [:before_yield]
      end
    end
  end

  it "works with an infinite enumerable" do
    s = 0..Float::INFINITY
    s.lazy.map { |n| n }.first(100).should ==
      s.first(100).map { |n| n }.to_a
  end

  it "doesn't unwrap Arrays" do
    Enumerator.new {|y| y.yield([1])}.lazy.to_a.should == [[1]]
  end
end
