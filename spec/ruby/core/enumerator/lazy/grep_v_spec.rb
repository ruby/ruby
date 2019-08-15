require_relative '../../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerator::Lazy#grep_v" do
  before(:each) do
    @yieldsmixed = EnumeratorLazySpecs::YieldsMixed.new.to_enum.lazy
    @eventsmixed = EnumeratorLazySpecs::EventsMixed.new.to_enum.lazy
    ScratchPad.record []
  end

  after(:each) do
    ScratchPad.clear
  end

  it "requires an argument" do
    Enumerator::Lazy.instance_method(:grep_v).arity.should == 1
  end

  it "returns a new instance of Enumerator::Lazy" do
    ret = @yieldsmixed.grep_v(Object) {}
    ret.should be_an_instance_of(Enumerator::Lazy)
    ret.should_not equal(@yieldsmixed)

    ret = @yieldsmixed.grep_v(Object)
    ret.should be_an_instance_of(Enumerator::Lazy)
    ret.should_not equal(@yieldsmixed)
  end

  it "sets #size to nil" do
    Enumerator::Lazy.new(Object.new, 100) {}.grep_v(Object) {}.size.should == nil
    Enumerator::Lazy.new(Object.new, 100) {}.grep_v(Object).size.should == nil
  end

  it "sets $~ in the block" do
    "z" =~ /z/ # Reset $~
    ["abc", "def"].lazy.grep_v(/e/) { |e|
      e.should == "abc"
      $~.should == nil
    }.force

    # Set by the match of "def"
    $&.should == "e"
  end

  it "sets $~ in the next block with each" do
    "z" =~ /z/ # Reset $~
    ["abc", "def"].lazy.grep_v(/e/).each { |e|
      e.should == "abc"
      $~.should == nil
    }

    # Set by the match of "def"
    $&.should == "e"
  end

  it "sets $~ in the next block with map" do
    "z" =~ /z/ # Reset $~
    ["abc", "def"].lazy.grep_v(/e/).map { |e|
      e.should == "abc"
      $~.should == nil
    }.force

    # Set by the match of "def"
    $&.should == "e"
  end

  describe "when the returned lazy enumerator is evaluated by Enumerable#first" do
    it "stops after specified times when not given a block" do
      (0..Float::INFINITY).lazy.grep_v(3..5).first(3).should == [0, 1, 2]

      @eventsmixed.grep_v(Symbol).first(1)
      ScratchPad.recorded.should == [:before_yield]
    end

    it "stops after specified times when given a block" do
      (0..Float::INFINITY).lazy.grep_v(4..8, &:succ).first(3).should == [1, 2, 3]

      @eventsmixed.grep_v(Symbol) {}.first(1)
      ScratchPad.recorded.should == [:before_yield]
    end
  end

  it "calls the block with a gathered array when yield with multiple arguments" do
    yields = []
    @yieldsmixed.grep_v(Array) { |v| yields << v }.force
    yields.should == EnumeratorLazySpecs::YieldsMixed.gathered_non_array_yields

    @yieldsmixed.grep_v(Array).force.should == yields
  end

  describe "on a nested Lazy" do
    it "sets #size to nil" do
      Enumerator::Lazy.new(Object.new, 100) {}.grep_v(Object).grep_v(Object) {}.size.should == nil
      Enumerator::Lazy.new(Object.new, 100) {}.grep_v(Object).grep_v(Object).size.should == nil
    end

    describe "when the returned lazy enumerator is evaluated by Enumerable#first" do
      it "stops after specified times when not given a block" do
        (0..Float::INFINITY).lazy.grep_v(3..5).grep_v(6..10).first(3).should == [0, 1, 2]

        @eventsmixed.grep_v(Symbol).grep_v(String).first(1)
        ScratchPad.recorded.should == [:before_yield]
      end

      it "stops after specified times when given a block" do
        (0..Float::INFINITY).lazy
          .grep_v(1..2) { |n| n > 3 ? n : false }
          .grep_v(false) { |n| n.even? ? n : false }
          .first(3)
          .should == [4, false, 6]

        @eventsmixed.grep_v(Symbol) {}.grep_v(String) {}.first(1)
        ScratchPad.recorded.should == [:before_yield]
      end
    end
  end

  it "works with an infinite enumerable" do
    s = 0..Float::INFINITY
    s.lazy.grep_v(String).first(100).should ==
      s.first(100).grep_v(String)
  end
end
