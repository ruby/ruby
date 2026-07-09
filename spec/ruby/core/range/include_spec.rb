# encoding: binary
require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/cover_and_include'

describe "Range#include?" do
  it_behaves_like :range_cover_and_include, :include?

  describe "on string elements" do
    it "returns true if other is matched by element.succ" do
      ('a'..'c').include?('b').should == true
      ('a'...'c').include?('b').should == true
    end

    it "returns false if other is not matched by element.succ" do
      ('a'..'c').include?('bc').should == false
      ('a'...'c').include?('bc').should == false
    end

    it "returns whether object is an element of self using #== to compare" do
      range = 'a'..'ab'
      range.include?('b').should == true
      range.include?('aa').should == true
      range.include?('ac').should == false
    end

    it "ignores self.end if excluded end" do
      range = 'a'...'aa'
      range.include?('aa').should == false
    end

    it "returns false if backward range" do
      range = 'aa'..'a'
      range.include?('b').should == false
    end

    it "returns false if empty range" do
      range = 'aa'...'aa'
      range.include?('aa').should == false
    end

    it "raises TypeError for beginningless ranges" do
      -> { (..'aa').include?('a') }.should.raise(TypeError)
      -> { (..'aa').include?(Object.new) }.should.raise(TypeError)
    end

    it "raises TypeError for endless ranges" do
      -> {
        ('aa'..).include?(Object.new)
      }.should.raise(TypeError)
      -> {
        ('aa'..).include?('a')
      }.should.raise(TypeError)
    end

    it "returns false if an argument isn't comparable with range boundaries" do
      range = 'a'..'aa'
      range.include?(Object.new).should == false
    end

    it "returns false if an argument is empty" do
      range = 'a'..'aa'
      range.include?('').should == false
    end

    describe "argument conversion to String" do
      it "converts the passed argument to a String using #to_str" do
        range = 'a'..'aa'
        object = Object.new
        def object.to_str; 'b'; end
        range.include?(object).should == true
      end

      it "returns false if the passed argument does not respond to #to_str" do
        range = 'a'..'aa'
        range.include?(nil).should == false
        range.include?([]).should == false
      end

      it "raises a TypeError if the passed argument responds to #to_str but it returns non-String value" do
        range = 'a'..'aa'
        object = Object.new
        def object.to_str; 1; end
        -> {
          range.include?(object)
        }.should.raise(TypeError)
      end
    end
  end

  describe "with weird succ" do
    describe "when included end value" do
      before :each do
        @range = RangeSpecs::TenfoldSucc.new(1)..RangeSpecs::TenfoldSucc.new(99)
      end

      it "returns false if other is less than first element" do
        @range.include?(RangeSpecs::TenfoldSucc.new(0)).should == false
      end

      it "returns true if other is equal as first element" do
        @range.include?(RangeSpecs::TenfoldSucc.new(1)).should == true
      end

      it "returns true if other is matched by element.succ" do
        @range.include?(RangeSpecs::TenfoldSucc.new(10)).should == true
      end

      it "returns false if other is not matched by element.succ" do
        @range.include?(RangeSpecs::TenfoldSucc.new(2)).should == false
      end

      it "returns false if other is equal as last element but not matched by element.succ" do
        @range.include?(RangeSpecs::TenfoldSucc.new(99)).should == false
      end

      it "returns false if other is greater than last element but matched by element.succ" do
        @range.include?(RangeSpecs::TenfoldSucc.new(100)).should == false
      end
    end

    describe "when excluded end value" do
      before :each do
        @range = RangeSpecs::TenfoldSucc.new(1)...RangeSpecs::TenfoldSucc.new(99)
      end

      it "returns false if other is less than first element" do
        @range.include?(RangeSpecs::TenfoldSucc.new(0)).should == false
      end

      it "returns true if other is equal as first element" do
        @range.include?(RangeSpecs::TenfoldSucc.new(1)).should == true
      end

      it "returns true if other is matched by element.succ" do
        @range.include?(RangeSpecs::TenfoldSucc.new(10)).should == true
      end

      it "returns false if other is not matched by element.succ" do
        @range.include?(RangeSpecs::TenfoldSucc.new(2)).should == false
      end

      it "returns false if other is equal as last element but not matched by element.succ" do
        @range.include?(RangeSpecs::TenfoldSucc.new(99)).should == false
      end

      it "returns false if other is greater than last element but matched by element.succ" do
        @range.include?(RangeSpecs::TenfoldSucc.new(100)).should == false
      end
    end
  end

  describe "with Time endpoints" do
    it "uses cover? logic" do
      now = Time.now
      range = (now..(now + 60))

      range.include?(now).should == true
      range.include?(now - 1).should == false
      range.include?(now + 60).should == true
      range.include?(now + 61).should == false
    end
  end

  it "does not include U+9995 in the range U+0999..U+9999" do
    ("\u{999}".."\u{9999}").include?("\u{9995}").should == false
  end

  describe "with custom Comparable objects (with #succ)" do
    it "returns whether object is an element of self using #== to compare" do
      range = RangeSpecs::WithSucc.new(1)..RangeSpecs::WithSucc.new(4)
      range.include?(RangeSpecs::WithSucc.new(2)).should == true
      range.include?(RangeSpecs::WithSucc.new(5)).should == false
    end

    it "ignores self.end if excluded end" do
      range = RangeSpecs::WithSucc.new(1)...RangeSpecs::WithSucc.new(4)
      range.include?(RangeSpecs::WithSucc.new(4)).should == false
    end

    it "returns false if backward range" do
      range = RangeSpecs::WithSucc.new(4)..RangeSpecs::WithSucc.new(1)
      range.include?(RangeSpecs::WithSucc.new(2)).should == false
    end

    it "returns false if empty range" do
      range = RangeSpecs::WithSucc.new(1)...RangeSpecs::WithSucc.new(1)
      range.include?(RangeSpecs::WithSucc.new(1)).should == false
    end

    it "returns false if an argument isn't comparable with range boundaries" do
      range = RangeSpecs::WithSucc.new(0)..RangeSpecs::WithSucc.new(6)
      range.include?(Object.new).should == false
    end

    it "raises TypeError for beginningless ranges" do
      -> {
        (..RangeSpecs::WithSucc.new(10)).include?(RangeSpecs::WithSucc.new(5))
      }.should.raise(TypeError)
    end

    it "raises TypeError for endless ranges" do
      -> {
        (RangeSpecs::WithSucc.new(0)..).include?(RangeSpecs::WithSucc.new(5))
      }.should.raise(TypeError)
    end
  end

  describe "with custom Comparable objects (without #succ)" do
    it "raises TypeError for beginningless ranges" do
      -> {
        (..RangeSpecs::WithoutSucc.new(10)).include?(RangeSpecs::WithoutSucc.new(5))
      }.should.raise(TypeError)

      -> {
        (..RangeSpecs::WithoutSucc.new(10)).include?(Object.new)
      }.should.raise(TypeError)
    end

    it "raises TypeError for endless ranges" do
      -> {
        (RangeSpecs::WithoutSucc.new(0)..).include?(RangeSpecs::WithoutSucc.new(5))
      }.should.raise(TypeError)

      -> {
        (RangeSpecs::WithoutSucc.new(0)..).include?(Object.new)
      }.should.raise(TypeError)
    end

    it "raises TypeError for (nil..nil)" do
      -> {
        (nil..nil).include?(Object.new)
      }.should.raise(TypeError)
    end
  end

  describe "with Numeric subclass elements" do
    it "returns true if object is between self.begin and self.end" do
      range = RangeSpecs::Number.new(0)..RangeSpecs::Number.new(6)
      range.include?(RangeSpecs::Number.new(5)).should == true
    end

    it "returns false if object is smaller than self.begin" do
      range = RangeSpecs::Number.new(0)..RangeSpecs::Number.new(6)
      range.include?(RangeSpecs::Number.new(-5)).should == false
    end

    it "returns false if object is greater than self.end" do
      range = RangeSpecs::Number.new(0)..RangeSpecs::Number.new(6)
      range.include?(RangeSpecs::Number.new(10)).should == false
    end

    it "ignores end if excluded end" do
      range = RangeSpecs::Number.new(0)...RangeSpecs::Number.new(6)
      range.include?(RangeSpecs::Number.new(6)).should == false
    end

    it "returns true if argument is a single element in the range" do
      range = RangeSpecs::Number.new(0)..RangeSpecs::Number.new(0)
      range.include?(RangeSpecs::Number.new(0)).should == true
    end

    it "returns false if range is empty" do
      range = RangeSpecs::Number.new(0)...RangeSpecs::Number.new(0)
      range.include?(RangeSpecs::Number.new(0)).should == false
    end

    it "returns false if an argument isn't comparable with range boundaries" do
      range = RangeSpecs::Number.new(0)..RangeSpecs::Number.new(6)
      range.include?(Object.new).should == false
    end

    describe "beginningless range" do
      it "returns false if object is greater than self.end" do
        range = ..RangeSpecs::Number.new(6)
        range.include?(RangeSpecs::Number.new(10)).should == false
      end

      it "returns true if object is smaller than self.end" do
        range = ..RangeSpecs::Number.new(6)
        range.include?(RangeSpecs::Number.new(0)).should == true
      end
    end

    describe "endless range" do
      it "returns true if object is greater than self.begin" do
        range = (RangeSpecs::Number.new(0)..)
        range.include?(RangeSpecs::Number.new(10)).should == true
      end

      it "returns false if object is smaller than self.begin" do
        range = (RangeSpecs::Number.new(0)..)
        range.include?(RangeSpecs::Number.new(-10)).should == false
      end
    end

    it "returns false if object isn't comparable with self.begin and self.end (that's #<=> returns nil)" do
      range = RangeSpecs::Number.new(0)..RangeSpecs::Number.new(6)
      object = Object.new
      def object.<=>(other); nil; end
      range.include?(object).should == false
    end
  end

  describe "with Time elements" do
    it "returns true if object is between self.begin and self.end" do
      range = Time.at(1_700_000_000)..Time.at(1_700_000_000 + 6)
      range.include?(Time.at(1_700_000_000 + 5)).should == true
    end

    it "returns false if object is smaller than self.begin" do
      range = Time.at(1_700_000_000)..Time.at(1_700_000_000 + 6)
      range.include?(Time.at(1_700_000_000 - 5)).should == false
    end

    it "returns false if object is greater than self.end" do
      range = Time.at(1_700_000_000)..Time.at(1_700_000_000 + 6)
      range.include?(Time.at(1_700_000_000 + 10)).should == false
    end

    it "ignores end if excluded end" do
      range = Time.at(1_700_000_000)...Time.at(1_700_000_000 + 6)
      range.include?(Time.at(1_700_000_000 + 6)).should == false
    end

    it "returns true if argument is a single element in the range" do
      range = Time.at(1_700_000_000)..Time.at(1_700_000_000)
      range.include?(Time.at(1_700_000_000)).should == true
    end

    it "returns false if range is empty" do
      range = Time.at(1_700_000_000)...Time.at(1_700_000_000)
      range.include?(Time.at(1_700_000_000)).should == false
    end

    it "returns false if an argument isn't comparable with range boundaries" do
      range = Time.at(1_700_000_000)..Time.at(1_700_000_000 + 6)
      range.include?(Object.new).should == false
    end

    describe "beginningless range" do
      it "returns false if object is greater than self.end" do
        range = ..Time.at(1_700_000_000 + 6)
        range.include?(Time.at(1_700_000_000 + 10)).should == false
      end

      it "returns true if object is smaller than self.end" do
        range = ..Time.at(1_700_000_000 + 6)
        range.include?(Time.at(1_700_000_000)).should == true
      end
    end

    describe "endless range" do
      it "returns true if object is greater than self.begin" do
        range = (Time.at(1_700_000_000)..)
        range.include?(Time.at(1_700_000_000 + 10)).should == true
      end

      it "returns false if object is smaller than self.begin" do
        range = (Time.at(1_700_000_000 + 10)..)
        range.include?(Time.at(1_700_000_000)).should == false
      end
    end

    it "returns false if object isn't comparable with self.begin and self.end (that's #<=> returns nil)" do
      range = Time.at(1_700_000_000)..Time.at(1_700_000_000 + 6)
      object = Object.new
      def object.<=>(other); nil; end
      range.include?(object).should == false
    end
  end

  describe 'with beginless and endless range' do
    it "return true for any Numeric value" do
      (nil..nil).include?(1).should == true
      (nil..nil).include?(1.0).should == true
      (nil..nil).include?(1r).should == true
      (nil..nil).include?(Complex(1)).should == true
      (nil..nil).include?(RangeSpecs::Number.new(1)).should == true
    end

    it "return true for any Time value" do
      (nil..nil).include?(Time.now).should == true
    end

    it "raises TypeError for non-Numeric/Time values" do
      -> { (nil..nil).include?("a") }.should.raise(TypeError)
      -> { (nil..nil).include?(:a) }.should.raise(TypeError)
      -> { (nil..nil).include?([]) }.should.raise(TypeError)
    end
  end
end
