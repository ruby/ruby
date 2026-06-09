require_relative '../../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerator::Lazy#flat_map" do
  before :each do
    @yieldsmixed = EnumeratorLazySpecs::YieldsMixed.new.to_enum.lazy
    @eventsmixed = EnumeratorLazySpecs::EventsMixed.new.to_enum.lazy
    ScratchPad.record []
  end

  after :each do
    ScratchPad.clear
  end

  it "returns a new instance of Enumerator::Lazy" do
    ret = @yieldsmixed.flat_map {}
    ret.should.instance_of?(Enumerator::Lazy)
    ret.should_not.equal?(@yieldsmixed)
  end

  it "sets #size to nil" do
    Enumerator::Lazy.new(Object.new, 100) {}.flat_map { true }.size.should == nil
  end

  describe "when the returned lazy enumerator is evaluated by Enumerable#first" do
    it "stops after specified times" do
      (0..Float::INFINITY).lazy.flat_map { |n| (n * 10).to_s }.first(6).should == %w[0 10 20 30 40 50]

      @eventsmixed.flat_map {}.first(1)
      ScratchPad.recorded.should == [:before_yield]
    end

    it "flattens elements when the given block returned an array or responding to .each and .force" do
      (0..Float::INFINITY).lazy.flat_map { |n| (n * 10).to_s.chars }.first(6).should == %w[0 1 0 2 0 3]
      (0..Float::INFINITY).lazy.flat_map { |n| (n * 10).to_s.each_char }.first(6).all? { |o| o.instance_of? Enumerator }.should == true
      (0..Float::INFINITY).lazy.flat_map { |n| (n * 10).to_s.each_char.lazy }.first(6).should == %w[0 1 0 2 0 3]
    end
  end

  it "calls the block with initial values when yield with multiple arguments" do
    yields = []
    @yieldsmixed.flat_map { |v| yields << v }.force
    yields.should == EnumeratorLazySpecs::YieldsMixed.initial_yields
  end

  it "raises an ArgumentError when not given a block" do
    -> { @yieldsmixed.flat_map }.should.raise(ArgumentError)
  end

  describe "on a nested Lazy" do
    it "sets #size to nil" do
      Enumerator::Lazy.new(Object.new, 100) {}.take(50) {}.flat_map {}.size.should == nil
    end

    describe "when the returned lazy enumerator is evaluated by Enumerable#first" do
      it "stops after specified times" do
        (0..Float::INFINITY).lazy.map {|n| n * 10 }.flat_map { |n| n.to_s }.first(6).should == %w[0 10 20 30 40 50]

        @eventsmixed.flat_map {}.flat_map {}.first(1)
        ScratchPad.recorded.should == [:before_yield]
      end

      it "flattens elements when the given block returned an array or responding to .each and .force" do
        (0..Float::INFINITY).lazy.map {|n| n * 10 }.flat_map { |n| n.to_s.chars }.first(6).should == %w[0 1 0 2 0 3]
        (0..Float::INFINITY).lazy.map {|n| n * 10 }.flat_map { |n| n.to_s.each_char }.first(6).all? { |o| o.instance_of? Enumerator }.should == true
        (0..Float::INFINITY).lazy.map {|n| n * 10 }.flat_map { |n| n.to_s.each_char.lazy }.first(6).should == %w[0 1 0 2 0 3]
      end
    end
  end

  it "works with an infinite enumerable" do
    s = 0..Float::INFINITY
    s.lazy.flat_map { |n| [-n, +n] }.first(200).should ==
      s.first(100).flat_map { |n| [-n, +n] }.to_a
  end

  it "properly unwraps nested yields" do
    s = Enumerator.new do |y| loop do y << [1, 2] end end

    expected = s.take(3).flat_map { |x| x }.to_a
    actual = s.lazy.take(3).flat_map{ |x| x }.force
    actual.should == expected
  end
end
