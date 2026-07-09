require_relative '../../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerator::Lazy#select" do
  before :each do
    @yieldsmixed = EnumeratorLazySpecs::YieldsMixed.new.to_enum.lazy
    @eventsmixed = EnumeratorLazySpecs::EventsMixed.new.to_enum.lazy
    ScratchPad.record []
  end

  after :each do
    ScratchPad.clear
  end

  it "returns a new instance of Enumerator::Lazy" do
    ret = @yieldsmixed.select {}
    ret.should.instance_of?(Enumerator::Lazy)
    ret.should_not.equal?(@yieldsmixed)
  end

  it "sets #size to nil" do
    Enumerator::Lazy.new(Object.new, 100) {}.select { true }.size.should == nil
  end

  describe "when the returned lazy enumerator is evaluated by Enumerable#first" do
    it "stops after specified times" do
      (0..Float::INFINITY).lazy.select(&:even?).first(3).should == [0, 2, 4]

      @eventsmixed.select { true }.first(1)
      ScratchPad.recorded.should == [:before_yield]
    end
  end

  it "calls the block with a gathered array when yield with multiple arguments" do
    yields = []
    @yieldsmixed.select { |v| yields << v }.force
    yields.should == EnumeratorLazySpecs::YieldsMixed.gathered_yields
  end

  it "raises an ArgumentError when not given a block" do
    -> { @yieldsmixed.select }.should.raise(ArgumentError)
  end

  describe "on a nested Lazy" do
    it "sets #size to nil" do
      Enumerator::Lazy.new(Object.new, 100) {}.take(50) {}.select { true }.size.should == nil
    end

    describe "when the returned lazy enumerator is evaluated by Enumerable#first" do
      it "stops after specified times" do
        (0..Float::INFINITY).lazy.select { |n| n > 5 }.select(&:even?).first(3).should == [6, 8, 10]

        @eventsmixed.select { true }.select { true }.first(1)
        ScratchPad.recorded.should == [:before_yield]
      end
    end
  end

  it "works with an infinite enumerable" do
    s = 0..Float::INFINITY
    s.lazy.select { |n| true }.first(100).should ==
      s.first(100).select { |n| true }
  end

  it "doesn't pre-evaluate the next element" do
    eval_count = 0
    enum = %w[Text1 Text2 Text3].lazy.select do
      eval_count += 1
      true
    end

    eval_count.should == 0
    enum.next
    eval_count.should == 1
  end

  it "doesn't over-evaluate when peeked" do
    eval_count = 0
    enum = %w[Text1 Text2 Text3].lazy.select do
      eval_count += 1
      true
    end

    eval_count.should == 0
    enum.peek
    enum.peek
    eval_count.should == 1
  end

  it "doesn't re-evaluate after peek" do
    eval_count = 0
    enum = %w[Text1 Text2 Text3].lazy.select do
      eval_count += 1
      true
    end

    eval_count.should == 0
    enum.peek
    eval_count.should == 1
    enum.next
    eval_count.should == 1
  end
end
