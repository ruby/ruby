require_relative '../../spec_helper'
require_relative '../array/shared/iterable_and_tolerating_size_increasing'
require_relative 'fixtures/classes'

describe "Enumerable#inject" do
  it "with argument takes a block with an accumulator (with argument as initial value) and the current element. Value of block becomes new accumulator" do
    a = []
    EnumerableSpecs::Numerous.new.inject(0) { |memo, i| a << [memo, i]; i }
    a.should == [[0, 2], [2, 5], [5, 3], [3, 6], [6, 1], [1, 4]]
    EnumerableSpecs::EachDefiner.new(true, true, true).inject(nil) {|result, i| i && result}.should == nil
  end

  it "produces an array of the accumulator and the argument when given a block with a *arg" do
    a = []
    [1,2].inject(0) {|*args| a << args; args[0] + args[1]}
    a.should == [[0, 1], [1, 2]]
  end

  it "can take two argument" do
    EnumerableSpecs::Numerous.new(1, 2, 3).inject(10, :-).should == 4
    EnumerableSpecs::Numerous.new(1, 2, 3).inject(10, "-").should == 4

    [1, 2, 3].inject(10, :-).should == 4
    [1, 2, 3].inject(10, "-").should == 4
  end

  it "converts non-Symbol method name argument to String with #to_str if two arguments" do
    name = Object.new
    def name.to_str; "-"; end

    EnumerableSpecs::Numerous.new(1, 2, 3).inject(10, name).should == 4
    [1, 2, 3].inject(10, name).should == 4
  end

  it "raises TypeError when the second argument is not Symbol or String and it cannot be converted to String if two arguments" do
    -> { EnumerableSpecs::Numerous.new(1, 2, 3).inject(10, Object.new) }.should.raise(TypeError, /is not a symbol nor a string/)
    -> { [1, 2, 3].inject(10, Object.new) }.should.raise(TypeError, /is not a symbol nor a string/)
  end

  it "ignores the block if two arguments" do
    -> {
      EnumerableSpecs::Numerous.new(1, 2, 3).inject(10, :-) { raise "we never get here"}.should == 4
    }.should complain(/#{__FILE__}:#{__LINE__-1}: warning: given block not used/, verbose: true)

    -> {
      [1, 2, 3].inject(10, :-) { raise "we never get here"}.should == 4
    }.should complain(/#{__FILE__}:#{__LINE__-1}: warning: given block not used/, verbose: true)
  end

  it "does not warn when given a Symbol with $VERBOSE true" do
    -> {
      [1, 2].inject(0, :+)
      [1, 2].inject(:+)
      EnumerableSpecs::Numerous.new(1, 2).inject(0, :+)
      EnumerableSpecs::Numerous.new(1, 2).inject(:+)
    }.should_not complain(verbose: true)
  end

  it "can take a symbol argument" do
    EnumerableSpecs::Numerous.new(10, 1, 2, 3).inject(:-).should == 4
    [10, 1, 2, 3].inject(:-).should == 4
  end

  it "can take a String argument" do
    EnumerableSpecs::Numerous.new(10, 1, 2, 3).inject("-").should == 4
    [10, 1, 2, 3].inject("-").should == 4
  end

  it "converts non-Symbol method name argument to String with #to_str" do
    name = Object.new
    def name.to_str; "-"; end

    EnumerableSpecs::Numerous.new(10, 1, 2, 3).inject(name).should == 4
    [10, 1, 2, 3].inject(name).should == 4
  end

  it "raises TypeError when passed not Symbol or String method name argument and it cannot be converted to String" do
    -> { EnumerableSpecs::Numerous.new(10, 1, 2, 3).inject(Object.new) }.should.raise(TypeError, /is not a symbol nor a string/)
    -> { [10, 1, 2, 3].inject(Object.new) }.should.raise(TypeError, /is not a symbol nor a string/)
  end

  it "without argument takes a block with an accumulator (with first element as initial value) and the current element. Value of block becomes new accumulator" do
    a = []
    EnumerableSpecs::Numerous.new.inject { |memo, i| a << [memo, i]; i }
    a.should == [[2, 5], [5, 3], [3, 6], [6, 1], [1, 4]]
  end

  it "gathers whole arrays as elements when each yields multiple" do
    multi = EnumerableSpecs::YieldsMulti.new
    multi.inject([]) {|acc, e| acc << e }.should == [[1, 2], [3, 4, 5], [6, 7, 8, 9]]
  end

  it "with inject arguments(legacy rubycon)" do
    # with inject argument
    EnumerableSpecs::EachDefiner.new().inject(1) {|acc,x| 999 }.should == 1
    EnumerableSpecs::EachDefiner.new(2).inject(1) {|acc,x| 999 }.should ==  999
    EnumerableSpecs::EachDefiner.new(2).inject(1) {|acc,x| acc }.should == 1
    EnumerableSpecs::EachDefiner.new(2).inject(1) {|acc,x| x }.should == 2

    EnumerableSpecs::EachDefiner.new(1,2,3,4).inject(100) {|acc,x| acc + x }.should == 110
    EnumerableSpecs::EachDefiner.new(1,2,3,4).inject(100) {|acc,x| acc * x }.should == 2400

    EnumerableSpecs::EachDefiner.new('a','b','c').inject("z") {|result, i| i+result}.should == "cbaz"
  end

  it "without inject arguments(legacy rubycon)" do
    # no inject argument
    EnumerableSpecs::EachDefiner.new(2).inject {|acc,x| 999 }.should == 2
    EnumerableSpecs::EachDefiner.new(2).inject {|acc,x| acc }.should == 2
    EnumerableSpecs::EachDefiner.new(2).inject {|acc,x| x }.should == 2

    EnumerableSpecs::EachDefiner.new(1,2,3,4).inject {|acc,x| acc + x }.should == 10
    EnumerableSpecs::EachDefiner.new(1,2,3,4).inject {|acc,x| acc * x }.should == 24

    EnumerableSpecs::EachDefiner.new('a','b','c').inject {|result, i| i+result}.should == "cba"
    EnumerableSpecs::EachDefiner.new(3, 4, 5).inject {|result, i| result*i}.should == 60
    EnumerableSpecs::EachDefiner.new([1], 2, 'a','b').inject {|r,i| r<<i}.should == [1, 2, 'a', 'b']
  end

  it "returns nil when fails(legacy rubycon)" do
    EnumerableSpecs::EachDefiner.new().inject {|acc,x| 999 }.should == nil
  end

  it "tolerates increasing a collection size during iterating Array" do
    array = [:a, :b, :c]
    ScratchPad.record []
    i = 0

    array.inject(nil) do |_, e|
      ScratchPad << e
      array << i if i < 100
      i += 1
    end

    actual = ScratchPad.recorded
    expected = [:a, :b, :c] + (0..99).to_a
    actual.sort_by(&:to_s).should == expected.sort_by(&:to_s)
  end

  it "raises an ArgumentError when no parameters or block is given" do
    -> { [1,2].inject }.should.raise(ArgumentError)
    -> { {one: 1, two: 2}.inject }.should.raise(ArgumentError)
  end
end
