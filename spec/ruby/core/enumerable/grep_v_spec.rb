require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerable#grep_v" do
  before :each do
    @numerous = EnumerableSpecs::Numerous.new(*(0..9).to_a)
    def (@odd_matcher = BasicObject.new).===(obj)
      obj.odd?
    end
  end

  it "sets $~ in the block" do
    "z" =~ /z/ # Reset $~
    ["abc", "def"].grep_v(/e/) { |e|
      e.should == "abc"
      $~.should == nil
    }

    # Set by the match of "def"
    $&.should == "e"
  end

  ruby_version_is ""..."3.0.0" do
    it "sets $~ to the last match when given no block" do
      "z" =~ /z/ # Reset $~
      ["abc", "def"].grep_v(/e/).should == ["abc"]

      # Set by the match of "def"
      $&.should == "e"

      ["abc", "def"].grep_v(/b/)
      $&.should == nil
    end
  end

  ruby_version_is "3.0.0" do
    it "does not set $~ when given no block" do
      "z" =~ /z/ # Reset $~
      ["abc", "def"].grep_v(/e/).should == ["abc"]
      $&.should == "z"
    end

    it "does not modify Regexp.last_match without block" do
      "z" =~ /z/ # Reset last match
      ["abc", "def"].grep_v(/e/).should == ["abc"]
      Regexp.last_match[0].should == "z"
    end
  end

  describe "without block" do
    it "returns an Array of matched elements" do
      @numerous.grep_v(@odd_matcher).should == [0, 2, 4, 6, 8]
    end

    it "compares pattern with gathered array when yielded with multiple arguments" do
      (unmatcher = Object.new).stub!(:===).and_return(false)
      EnumerableSpecs::YieldsMixed2.new.grep_v(unmatcher).should == EnumerableSpecs::YieldsMixed2.gathered_yields
    end

    it "raises an ArgumentError when not given a pattern" do
      -> { @numerous.grep_v }.should raise_error(ArgumentError)
    end
  end

  describe "with block" do
    it "returns an Array of matched elements that mapped by the block" do
      @numerous.grep_v(@odd_matcher) { |n| n * 2 }.should == [0, 4, 8, 12, 16]
    end

    it "calls the block with gathered array when yielded with multiple arguments" do
      (unmatcher = Object.new).stub!(:===).and_return(false)
      EnumerableSpecs::YieldsMixed2.new.grep_v(unmatcher){ |e| e }.should == EnumerableSpecs::YieldsMixed2.gathered_yields
    end

    it "raises an ArgumentError when not given a pattern" do
      -> { @numerous.grep_v { |e| e } }.should raise_error(ArgumentError)
    end
  end
end
