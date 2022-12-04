require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerable#none?" do
  before :each do
    @empty = EnumerableSpecs::Empty.new
    @enum = EnumerableSpecs::Numerous.new
    @enum1 = EnumerableSpecs::Numerous.new(0, 1, 2, -1)
    @enum2 = EnumerableSpecs::Numerous.new(nil, false, true)
  end

  it "always returns true on empty enumeration" do
    @empty.should.none?
    @empty.none? { true }.should == true
  end

  it "raises an ArgumentError when more than 1 argument is provided" do
    -> { @enum.none?(1, 2, 3) }.should raise_error(ArgumentError)
    -> { [].none?(1, 2, 3) }.should raise_error(ArgumentError)
    -> { {}.none?(1, 2, 3) }.should raise_error(ArgumentError)
  end

  it "does not hide exceptions out of #each" do
    -> {
      EnumerableSpecs::ThrowingEach.new.none?
    }.should raise_error(RuntimeError)

    -> {
      EnumerableSpecs::ThrowingEach.new.none? { false }
    }.should raise_error(RuntimeError)
  end

  describe "with no block" do
    it "returns true if none of the elements in self are true" do
      e = EnumerableSpecs::Numerous.new(false, nil, false)
      e.none?.should be_true
    end

    it "returns false if at least one of the elements in self are true" do
      e = EnumerableSpecs::Numerous.new(false, nil, true, false)
      e.none?.should be_false
    end

    it "gathers whole arrays as elements when each yields multiple" do
      multi = EnumerableSpecs::YieldsMultiWithFalse.new
      multi.none?.should be_false
    end
  end

  describe "with a block" do
    before :each do
      @e = EnumerableSpecs::Numerous.new(1,1,2,3,4)
    end

    it "passes each element to the block in turn until it returns true" do
      acc = []
      @e.none? {|e| acc << e; false }
      acc.should == [1,1,2,3,4]
    end

    it "stops passing elements to the block when it returns true" do
      acc = []
      @e.none? {|e| acc << e; e == 3 ? true : false }
      acc.should == [1,1,2,3]
    end

    it "returns true if the block never returns true" do
      @e.none? {|e| false }.should be_true
    end

    it "returns false if the block ever returns true" do
      @e.none? {|e| e == 3 ? true : false }.should be_false
    end

    it "does not hide exceptions out of the block" do
      -> {
        @enum.none? { raise "from block" }
      }.should raise_error(RuntimeError)
    end

    it "gathers initial args as elements when each yields multiple" do
      multi = EnumerableSpecs::YieldsMulti.new
      yielded = []
      multi.none? { |e| yielded << e; false }
      yielded.should == [1, 3, 6]
    end

    it "yields multiple arguments when each yields multiple" do
      multi = EnumerableSpecs::YieldsMulti.new
      yielded = []
      multi.none? { |*args| yielded << args; false }
      yielded.should == [[1, 2], [3, 4, 5], [6, 7, 8, 9]]
    end
  end

  describe 'when given a pattern argument' do
    it "calls `===` on the pattern the return value " do
      pattern = EnumerableSpecs::Pattern.new { |x| x == 3 }
      @enum1.none?(pattern).should == true
      pattern.yielded.should == [[0], [1], [2], [-1]]
    end

    it "always returns true on empty enumeration" do
      @empty.none?(Integer).should == true
      [].none?(Integer).should == true
      {}.none?(NilClass).should == true
    end

    it "does not hide exceptions out of #each" do
      -> {
        EnumerableSpecs::ThrowingEach.new.none?(Integer)
      }.should raise_error(RuntimeError)
    end

    it "returns true if the pattern never returns a truthy value" do
      @enum2.none?(Integer).should == true
      pattern = EnumerableSpecs::Pattern.new { |x| nil }
      @enum.none?(pattern).should == true

      [1, 42, 3].none?(pattern).should == true
      {a: 1, b: 2}.none?(pattern).should == true
    end

    it "returns false if the pattern ever returns other than false or nil" do
      pattern = EnumerableSpecs::Pattern.new { |x| x < 0 }
      @enum1.none?(pattern).should == false
      pattern.yielded.should == [[0], [1], [2], [-1]]

      [1, 2, 3, -1].none?(pattern).should == false
      {a: 1}.none?(Array).should == false
    end

    it "does not hide exceptions out of pattern#===" do
      pattern = EnumerableSpecs::Pattern.new { raise "from pattern" }
      -> {
        @enum.none?(pattern)
      }.should raise_error(RuntimeError)
    end

    it "calls the pattern with gathered array when yielded with multiple arguments" do
      multi = EnumerableSpecs::YieldsMulti.new
      pattern = EnumerableSpecs::Pattern.new { false }
      multi.none?(pattern).should == true
      pattern.yielded.should == [[[1, 2]], [[3, 4, 5]], [[6, 7, 8, 9]]]
    end
  end
end
