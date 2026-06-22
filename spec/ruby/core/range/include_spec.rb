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
end
