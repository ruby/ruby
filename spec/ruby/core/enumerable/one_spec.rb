require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerable#one?" do
  before :each do
    @empty = EnumerableSpecs::Empty.new
    @enum = EnumerableSpecs::Numerous.new
    @enum1 = EnumerableSpecs::Numerous.new(0, 1, 2, -1)
    @enum2 = EnumerableSpecs::Numerous.new(nil, false, true)
  end

  it "always returns false on empty enumeration" do
    @empty.should_not.one?
    @empty.one? { true }.should == false
  end

  it "raises an ArgumentError when more than 1 argument is provided" do
    -> { @enum.one?(1, 2, 3) }.should raise_error(ArgumentError)
    -> { [].one?(1, 2, 3) }.should raise_error(ArgumentError)
    -> { {}.one?(1, 2, 3) }.should raise_error(ArgumentError)
  end

  it "does not hide exceptions out of #each" do
    -> {
      EnumerableSpecs::ThrowingEach.new.one?
    }.should raise_error(RuntimeError)

    -> {
      EnumerableSpecs::ThrowingEach.new.one? { false }
    }.should raise_error(RuntimeError)
  end

  describe "with no block" do
    it "returns true if only one element evaluates to true" do
      [false, nil, true].one?.should be_true
    end

    it "returns false if two elements evaluate to true" do
      [false, :value, nil, true].one?.should be_false
    end

    it "returns false if all elements evaluate to false" do
      [false, nil, false].one?.should be_false
    end

    it "gathers whole arrays as elements when each yields multiple" do
      multi = EnumerableSpecs::YieldsMultiWithSingleTrue.new
      multi.one?.should be_false
    end
  end

  describe "with a block" do
    it "returns true if block returns true once" do
      [:a, :b, :c].one? { |s| s == :a }.should be_true
    end

    it "returns false if the block returns true more than once" do
      [:a, :b, :c].one? { |s| s == :a || s == :b }.should be_false
    end

    it "returns false if the block only returns false" do
      [:a, :b, :c].one? { |s| s == :d }.should be_false
    end

    it "does not hide exceptions out of the block" do
      -> {
        @enum.one? { raise "from block" }
      }.should raise_error(RuntimeError)
    end

    it "gathers initial args as elements when each yields multiple" do
      multi = EnumerableSpecs::YieldsMulti.new
      yielded = []
      multi.one? { |e| yielded << e; false }.should == false
      yielded.should == [1, 3, 6]
    end

    it "yields multiple arguments when each yields multiple" do
      multi = EnumerableSpecs::YieldsMulti.new
      yielded = []
      multi.one? { |*args| yielded << args; false }.should == false
      yielded.should == [[1, 2], [3, 4, 5], [6, 7, 8, 9]]
    end
  end

  describe 'when given a pattern argument' do
    it "calls `===` on the pattern the return value " do
      pattern = EnumerableSpecs::Pattern.new { |x| x == 1 }
      @enum1.one?(pattern).should == true
      pattern.yielded.should == [[0], [1], [2], [-1]]
    end

    it "always returns false on empty enumeration" do
      @empty.one?(Integer).should == false
      [].one?(Integer).should == false
      {}.one?(NilClass).should == false
    end

    it "does not hide exceptions out of #each" do
      -> {
        EnumerableSpecs::ThrowingEach.new.one?(Integer)
      }.should raise_error(RuntimeError)
    end

    it "returns true if the pattern returns a truthy value only once" do
      @enum2.one?(NilClass).should == true
      pattern = EnumerableSpecs::Pattern.new { |x| x == 2 }
      @enum1.one?(pattern).should == true

      [1, 2, 42, 3].one?(pattern).should == true

      pattern = EnumerableSpecs::Pattern.new { |x| x == [:b, 2] }
      {a: 1, b: 2}.one?(pattern).should == true
    end

    it "returns false if the pattern returns a truthy value more than once" do
      pattern = EnumerableSpecs::Pattern.new { |x| !x }
      @enum2.one?(pattern).should == false
      pattern.yielded.should == [[nil], [false]]

      [1, 2, 3].one?(Integer).should == false
      {a: 1, b: 2}.one?(Array).should == false
    end

    it "returns false if the pattern never returns a truthy value" do
      pattern = EnumerableSpecs::Pattern.new { |x| nil }
      @enum1.one?(pattern).should == false
      pattern.yielded.should == [[0], [1], [2], [-1]]

      [1, 2, 3].one?(pattern).should == false
      {a: 1}.one?(pattern).should == false
    end

    it "does not hide exceptions out of pattern#===" do
      pattern = EnumerableSpecs::Pattern.new { raise "from pattern" }
      -> {
        @enum.one?(pattern)
      }.should raise_error(RuntimeError)
    end

    it "calls the pattern with gathered array when yielded with multiple arguments" do
      multi = EnumerableSpecs::YieldsMulti.new
      pattern = EnumerableSpecs::Pattern.new { false }
      multi.one?(pattern).should == false
      pattern.yielded.should == [[[1, 2]], [[3, 4, 5]], [[6, 7, 8, 9]]]
    end

    it "ignores the block if there is an argument" do
      -> {
        EnumerableSpecs::Numerous.new(1, 2, 3, 4, "5").one?(String) { false }.should == true
      }.should complain(/given block not used/)
    end
  end
end
