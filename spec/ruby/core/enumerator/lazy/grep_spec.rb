# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerator::Lazy#grep" do
  before :each do
    @yieldsmixed = EnumeratorLazySpecs::YieldsMixed.new.to_enum.lazy
    @eventsmixed = EnumeratorLazySpecs::EventsMixed.new.to_enum.lazy
    ScratchPad.record []
  end

  after :each do
    ScratchPad.clear
  end

  it "requires an argument" do
    Enumerator::Lazy.instance_method(:grep).arity.should == 1
  end

  it "returns a new instance of Enumerator::Lazy" do
    ret = @yieldsmixed.grep(Object) {}
    ret.should be_an_instance_of(Enumerator::Lazy)
    ret.should_not equal(@yieldsmixed)

    ret = @yieldsmixed.grep(Object)
    ret.should be_an_instance_of(Enumerator::Lazy)
    ret.should_not equal(@yieldsmixed)
  end

  it "sets #size to nil" do
    Enumerator::Lazy.new(Object.new, 100) {}.grep(Object) {}.size.should == nil
    Enumerator::Lazy.new(Object.new, 100) {}.grep(Object).size.should == nil
  end

  it "sets $~ in the block" do
    "z" =~ /z/ # Reset $~
    ["abc", "def"].lazy.grep(/b/) { |e|
      e.should == "abc"
      $&.should == "b"
    }.force

    # Set by the failed match of "def"
    $~.should == nil
  end

  it "sets $~ in the next block with each" do
    "z" =~ /z/ # Reset $~
    ["abc", "def"].lazy.grep(/b/).each { |e|
      e.should == "abc"
      $&.should == "b"
    }

    # Set by the failed match of "def"
    $~.should == nil
  end

  it "sets $~ in the next block with map" do
    "z" =~ /z/ # Reset $~
    ["abc", "def"].lazy.grep(/b/).map { |e|
      e.should == "abc"
      $&.should == "b"
    }.force

    # Set by the failed match of "def"
    $~.should == nil
  end

  describe "when the returned lazy enumerator is evaluated by Enumerable#first" do
    it "stops after specified times when not given a block" do
      (0..Float::INFINITY).lazy.grep(Integer).first(3).should == [0, 1, 2]

      @eventsmixed.grep(BasicObject).first(1)
      ScratchPad.recorded.should == [:before_yield]
    end

    it "stops after specified times when given a block" do
      (0..Float::INFINITY).lazy.grep(Integer, &:succ).first(3).should == [1, 2, 3]

      @eventsmixed.grep(BasicObject) {}.first(1)
      ScratchPad.recorded.should == [:before_yield]
    end
  end

  it "calls the block with a gathered array when yield with multiple arguments" do
    yields = []
    @yieldsmixed.grep(BasicObject) { |v| yields << v }.force
    yields.should == EnumeratorLazySpecs::YieldsMixed.gathered_yields

    @yieldsmixed.grep(BasicObject).force.should == yields
  end

  describe "on a nested Lazy" do
    it "sets #size to nil" do
      Enumerator::Lazy.new(Object.new, 100) {}.grep(Object) {}.size.should == nil
      Enumerator::Lazy.new(Object.new, 100) {}.grep(Object).size.should == nil
    end

    describe "when the returned lazy enumerator is evaluated by Enumerable#first" do
      it "stops after specified times when not given a block" do
        (0..Float::INFINITY).lazy.grep(Integer).grep(Object).first(3).should == [0, 1, 2]

        @eventsmixed.grep(BasicObject).grep(Object).first(1)
        ScratchPad.recorded.should == [:before_yield]
      end

      it "stops after specified times when given a block" do
        (0..Float::INFINITY).lazy.grep(Integer) { |n| n > 3 ? n : false }.grep(Integer) { |n| n.even? ? n : false }.first(3).should == [4, false, 6]

        @eventsmixed.grep(BasicObject) {}.grep(Object) {}.first(1)
        ScratchPad.recorded.should == [:before_yield]
      end
    end
  end

  it "works with an infinite enumerable" do
    s = 0..Float::INFINITY
    s.lazy.grep(Numeric).first(100).should ==
      s.first(100).grep(Numeric)
  end
end
