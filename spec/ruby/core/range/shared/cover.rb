# -*- encoding: binary -*-
require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe :range_cover, shared: true do
  it "uses the range element's <=> to make the comparison" do
    a = mock('a')
    a.should_receive(:<=>).twice.and_return(-1,-1)
    (a..'z').send(@method, 'b').should be_true
  end

  it "uses a continuous inclusion test" do
    ('a'..'f').send(@method, 'aa').should be_true
    ('a'..'f').send(@method, 'babe').should be_true
    ('a'..'f').send(@method, 'baby').should be_true
    ('a'..'f').send(@method, 'ga').should be_false
    (-10..-2).send(@method, -2.5).should be_true
  end

  describe "on string elements" do
    it "returns true if other is matched by element.succ" do
      ('a'..'c').send(@method, 'b').should be_true
      ('a'...'c').send(@method, 'b').should be_true
    end

    it "returns true if other is not matched by element.succ" do
      ('a'..'c').send(@method, 'bc').should be_true
      ('a'...'c').send(@method, 'bc').should be_true
    end
  end

  describe "with weird succ" do
    describe "when included end value" do
      before :each do
        @range = RangeSpecs::TenfoldSucc.new(1)..RangeSpecs::TenfoldSucc.new(99)
      end

      it "returns false if other is less than first element" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(0)).should be_false
      end

      it "returns true if other is equal as first element" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(1)).should be_true
      end

      it "returns true if other is matched by element.succ" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(10)).should be_true
      end

      it "returns true if other is not matched by element.succ" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(2)).should be_true
      end

      it "returns true if other is equal as last element but not matched by element.succ" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(99)).should be_true
      end

      it "returns false if other is greater than last element but matched by element.succ" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(100)).should be_false
      end
    end

    describe "when excluded end value" do
      before :each do
        @range = RangeSpecs::TenfoldSucc.new(1)...RangeSpecs::TenfoldSucc.new(99)
      end

      it "returns false if other is less than first element" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(0)).should be_false
      end

      it "returns true if other is equal as first element" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(1)).should be_true
      end

      it "returns true if other is matched by element.succ" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(10)).should be_true
      end

      it "returns true if other is not matched by element.succ" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(2)).should be_true
      end

      it "returns false if other is equal as last element but not matched by element.succ" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(99)).should be_false
      end

      it "returns false if other is greater than last element but matched by element.succ" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(100)).should be_false
      end
    end
  end
end

describe :range_cover_subrange, shared: true do
  ruby_version_is "2.6" do
    context "range argument" do
      it "accepts range argument" do
        (0..10).send(@method, (3..7)).should be_true
        (0..10).send(@method, (3..15)).should be_false
        (0..10).send(@method, (-2..7)).should be_false

        (1.1..7.9).send(@method, (2.5..6.5)).should be_true
        (1.1..7.9).send(@method, (2.5..8.5)).should be_false
        (1.1..7.9).send(@method, (0.5..6.5)).should be_false

        ('c'..'i').send(@method, ('d'..'f')).should be_true
        ('c'..'i').send(@method, ('d'..'z')).should be_false
        ('c'..'i').send(@method, ('a'..'f')).should be_false

        range_10_100 = RangeSpecs::TenfoldSucc.new(10)..RangeSpecs::TenfoldSucc.new(100)
        range_20_90 = RangeSpecs::TenfoldSucc.new(20)..RangeSpecs::TenfoldSucc.new(90)
        range_20_110 = RangeSpecs::TenfoldSucc.new(20)..RangeSpecs::TenfoldSucc.new(110)
        range_0_90 = RangeSpecs::TenfoldSucc.new(0)..RangeSpecs::TenfoldSucc.new(90)

        range_10_100.send(@method, range_20_90).should be_true
        range_10_100.send(@method, range_20_110).should be_false
        range_10_100.send(@method, range_0_90).should be_false
      end

      it "supports boundaries of different comparable types" do
        (0..10).send(@method, (3.1..7.9)).should be_true
        (0..10).send(@method, (3.1..15.9)).should be_false
        (0..10).send(@method, (-2.1..7.9)).should be_false
      end

      it "returns false if types are not comparable" do
        (0..10).send(@method, ('a'..'z')).should be_false
        (0..10).send(@method, (RangeSpecs::TenfoldSucc.new(0)..RangeSpecs::TenfoldSucc.new(100))).should be_false
      end

      it "honors exclusion of right boundary (:exclude_end option)" do
        # Integer
        (0..10).send(@method, (0..10)).should be_true
        (0...10).send(@method, (0...10)).should be_true

        (0..10).send(@method, (0...10)).should be_true
        (0...10).send(@method, (0..10)).should be_false

        (0...11).send(@method, (0..10)).should be_true
        (0..10).send(@method, (0...11)).should be_true

        # Float
        (0..10.1).send(@method, (0..10.1)).should be_true
        (0...10.1).send(@method, (0...10.1)).should be_true

        (0..10.1).send(@method, (0...10.1)).should be_true
        (0...10.1).send(@method, (0..10.1)).should be_false

        (0...11.1).send(@method, (0..10.1)).should be_true
        (0..10.1).send(@method, (0...11.1)).should be_false
      end
    end
  end
end
