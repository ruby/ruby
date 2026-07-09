# encoding: binary
require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe :range_cover, shared: true do
  it "uses the range element's <=> to make the comparison" do
    a = mock('a')
    a.should_receive(:<=>).twice.and_return(-1,-1)
    (a..'z').send(@method, 'b').should == true
  end

  it "uses a continuous inclusion test" do
    ('a'..'f').send(@method, 'aa').should == true
    ('a'..'f').send(@method, 'babe').should == true
    ('a'..'f').send(@method, 'baby').should == true
    ('a'..'f').send(@method, 'ga').should == false
    (-10..-2).send(@method, -2.5).should == true
  end

  describe "on string elements" do
    it "returns true if other is matched by element.succ" do
      ('a'..'c').send(@method, 'b').should == true
      ('a'...'c').send(@method, 'b').should == true
    end

    it "returns true if other is not matched by element.succ" do
      ('a'..'c').send(@method, 'bc').should == true
      ('a'...'c').send(@method, 'bc').should == true
    end
  end

  describe "with weird succ" do
    describe "when included end value" do
      before :each do
        @range = RangeSpecs::TenfoldSucc.new(1)..RangeSpecs::TenfoldSucc.new(99)
      end

      it "returns false if other is less than first element" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(0)).should == false
      end

      it "returns true if other is equal as first element" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(1)).should == true
      end

      it "returns true if other is matched by element.succ" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(10)).should == true
      end

      it "returns true if other is not matched by element.succ" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(2)).should == true
      end

      it "returns true if other is equal as last element but not matched by element.succ" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(99)).should == true
      end

      it "returns false if other is greater than last element but matched by element.succ" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(100)).should == false
      end
    end

    describe "when excluded end value" do
      before :each do
        @range = RangeSpecs::TenfoldSucc.new(1)...RangeSpecs::TenfoldSucc.new(99)
      end

      it "returns false if other is less than first element" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(0)).should == false
      end

      it "returns true if other is equal as first element" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(1)).should == true
      end

      it "returns true if other is matched by element.succ" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(10)).should == true
      end

      it "returns true if other is not matched by element.succ" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(2)).should == true
      end

      it "returns false if other is equal as last element but not matched by element.succ" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(99)).should == false
      end

      it "returns false if other is greater than last element but matched by element.succ" do
        @range.send(@method, RangeSpecs::TenfoldSucc.new(100)).should == false
      end
    end
  end

  describe "with non-Range argument" do
    it "returns false if the object is smaller than self.begin" do
      (0..6).send(@method, -5).should == false
    end

    it "returns false if the object is greater than self.end" do
      (0..6).send(@method, 10).should == false
    end

    it "returns false if the range is empty" do
      (0...0).send(@method, 0).should == false
    end

    it "returns false if the argument is not comparable with the range elements (returns nil from <=>)" do
      (0..6).send(@method, Object.new).should == false
    end

    it "returns false if the argument is greater than self.end on a beginless range" do
      (...6).send(@method, 10).should == false
    end

    it "returns true if the argument is smaller than self.end on a beginless range" do
      (...6).send(@method, 0).should == true
    end

    it "returns true if the argument is greater than self.begin on an endless range" do
      (0..).send(@method, 10).should == true
    end

    it "returns false if the argument is smaller than self.begin on an endless range" do
      (0..).send(@method, -10).should == false
    end

    it "returns true on any value for (nil..nil)" do
      (nil..nil).send(@method, Object.new).should == true
    end

    it "returns true on any value for (nil...nil)" do
      (nil...nil).send(@method, Object.new).should == true
    end
  end
end

describe :range_cover_subrange, shared: true do
  it "accepts range argument" do
    (0..10).send(@method, (3..7)).should == true
    (0..10).send(@method, (3..15)).should == false
    (0..10).send(@method, (-2..7)).should == false

    (1.1..7.9).send(@method, (2.5..6.5)).should == true
    (1.1..7.9).send(@method, (2.5..8.5)).should == false
    (1.1..7.9).send(@method, (0.5..6.5)).should == false

    ('c'..'i').send(@method, ('d'..'f')).should == true
    ('c'..'i').send(@method, ('d'..'z')).should == false
    ('c'..'i').send(@method, ('a'..'f')).should == false

    range_10_100 = RangeSpecs::TenfoldSucc.new(10)..RangeSpecs::TenfoldSucc.new(100)
    range_20_90 = RangeSpecs::TenfoldSucc.new(20)..RangeSpecs::TenfoldSucc.new(90)
    range_20_110 = RangeSpecs::TenfoldSucc.new(20)..RangeSpecs::TenfoldSucc.new(110)
    range_0_90 = RangeSpecs::TenfoldSucc.new(0)..RangeSpecs::TenfoldSucc.new(90)

    range_10_100.send(@method, range_20_90).should == true
    range_10_100.send(@method, range_20_110).should == false
    range_10_100.send(@method, range_0_90).should == false
  end

  it "supports boundaries of different comparable types" do
    (0..10).send(@method, (3.1..7.9)).should == true
    (0..10).send(@method, (3.1..15.9)).should == false
    (0..10).send(@method, (-2.1..7.9)).should == false
  end

  it "returns false if types are not comparable" do
    (0..10).send(@method, ('a'..'z')).should == false
    (0..10).send(@method, (RangeSpecs::TenfoldSucc.new(0)..RangeSpecs::TenfoldSucc.new(100))).should == false
  end

  it "honors exclusion of right boundary (:exclude_end option)" do
    # Integer
    (0..10).send(@method, (0..10)).should == true
    (0...10).send(@method, (0...10)).should == true

    (0..10).send(@method, (0...10)).should == true
    (0...10).send(@method, (0..10)).should == false

    (0...11).send(@method, (0..10)).should == true
    (0..10).send(@method, (0...11)).should == true

    # Float
    (0..10.1).send(@method, (0..10.1)).should == true
    (0...10.1).send(@method, (0...10.1)).should == true

    (0..10.1).send(@method, (0...10.1)).should == true
    (0...10.1).send(@method, (0..10.1)).should == false

    (0...11.1).send(@method, (0..10.1)).should == true
    (0..10.1).send(@method, (0...11.1)).should == false
  end

  context "range argument with Integer boundaries" do
    context "when other range is completely inside self" do
      it "returns true if self.begin < other.begin and self.end > other.end" do
        (0..10).send(@method, 4..6).should == true
      end

      it "returns true if self.begin == other.begin and self.end > other.end" do
        (0..10).send(@method, 0..6).should == true
      end

      it "returns true if self.begin < other.begin and self.end == other.end" do
        (0..10).send(@method, 4..10).should == true
      end

      it "returns true if self.begin < other.begin and self.end < other.end but other.exclude_end? is true and the rightmost other value <= self.end" do
        (0..10).send(@method, 4...11).should == true
      end

      it "returns true if self.begin == other.begin and self.end == other.end" do
        (0..10).send(@method, 0..10).should == true
      end

      it "returns true if self.begin == other.begin and self.end == other.end and self.exclude_end? is true and other.exclude_end? is true" do
        (0...10).send(@method, 0...10).should == true
      end

      it "returns true if self is beginless and self.end > other.end" do
        (...10).send(@method, 4..6).should == true
      end

      it "returns true if self is beginless and self.end == other.end" do
        (..10).send(@method, 4..10).should == true
      end

      it "returns true if self is beginless and self.end == other.end and self.exclude_end? is true and other.exclude_end? is true" do
        (...10).send(@method, 4...10).should == true
      end

      it "returns true if self and other are beginless and self.end > other.end" do
        (...10).send(@method, (...6)).should == true
      end

      it "returns true if self and other are beginless and self.end == other.end and self.exclude_end? is true and other.exclude_end? is true" do
        (...10).send(@method, (...10)).should == true
      end

      it "returns true if self is beginless and self.end < other.end but other.exclude_end? is true and the rightmost other value <= self.end" do
        (..10).send(@method, 4...11).should == true
      end

      it "returns true if self is endless and self.begin < other.begin" do
        (0..).send(@method, 4..6).should == true
      end

      it "returns true if self is endless and self.begin == other.begin" do
        (0..).send(@method, 0..6).should == true
      end

      it "returns true if self and other are endless and self.begin < other.begin" do
        (0..).send(@method, (4..)).should == true
      end

      it "returns true if self and other are endless and self.begin == other.begin" do
        (0..).send(@method, (0..)).should == true
      end

      it "returns true if self and other are endless and self.begin < other.begin and self.exclude_end? is true and other.exclude_end? is true" do
        (0...).send(@method, (4...)).should == true
      end

      it "returns true if self and other are endless and self.begin == other.begin and self.exclude_end? is true and other.exclude_end? is true" do
        (0...).send(@method, (0...)).should == true
      end

      it "returns true if self is (nil..nil) and other is finite" do
        (nil..nil).send(@method, 4..6).should == true
      end

      it "returns true if self is (nil..nil) and other is beginless" do
        (nil..nil).send(@method, (...6)).should == true
      end

      it "returns true if self is (nil..nil) and other is endless" do
        (nil..nil).send(@method, (4..)).should == true
      end

      it "returns true if self is (nil...nil) and other is finite" do
        (nil...nil).send(@method, 4..6).should == true
      end

      it "returns true if self is (nil...nil) and other is beginless" do
        (nil...nil).send(@method, (...6)).should == true
      end

      it "returns true if self is (nil...nil) and other is endless and other.exclude_end? is true" do
        (nil...nil).send(@method, (4...)).should == true
      end
    end

    context "when other range is partially interleaved" do
      it "returns false if self.begin > other.begin, self.begin < other.end and self.end > other.end" do
        (4..10).send(@method, 0..6).should == false
      end

      it "returns false if self.begin > other.begin, self.begin < other.end and self.end == other.end" do
        (4..10).send(@method, 0..10).should == false
      end

      it "returns false if self.begin > other.begin, self.begin < other.end and self.end < other.end" do
        (4..6).send(@method, 0..10).should == false
      end

      it "returns false if self.begin < other.begin and self.end > other.begin, self.end < other.end" do
        (0..6).send(@method, 4..10).should == false
      end

      it "returns false if self.begin < other.begin and self.end == other.end and self.exclude_end? is true" do
        (0...10).send(@method, 6..10).should == false
      end

      it "returns false if self.begin < other.begin and self.end == other.begin" do
        (0..4).send(@method, 4..10).should == false
      end

      it "returns false if self is beginless and self.end > other.begin but self.end < other.end" do
        (...6).send(@method, 4..10).should == false
      end

      it "returns false if self is beginless and self.end == other.end but self.exclude_end? is true" do
        (...6).send(@method, 4..6).should == false
      end

      it "returns false if self and other are beginless but self.end < other.end" do
        (...6).send(@method, (...10)).should == false
      end

      it "returns false if self and other are beginless and self.end == other.end but self.exclude_end? is true" do
        (...10).send(@method, (..10)).should == false
      end

      it "returns false if self is endless and self.begin > other.begin" do
        (4..).send(@method, 0..6).should == false
      end

      it "returns false if self and other are endless and self.begin > other.begin" do
        (4..).send(@method, (0..)).should == false
      end

      it "returns false if self and other are endless and self.begin == other.begin but self.exclude_end? is true" do
        (0...).send(@method, (0..)).should == false
      end

      it "returns false if self and other are endless and self.begin < other.begin but self.exclude_end? is true" do
        (0...).send(@method, (4..)).should == false
      end

      it "returns false if self is (nil...nil) and other is endless" do
        (nil...nil).send(@method, (4..)).should == false
      end

      it "returns false if self is beginless and other is endless and self.end == other.begin" do
        (..10).send(@method, (10..)).should == false
      end

      it "returns false if other is beginless and self is endless and other.end == self.begin" do
        (10..).send(@method, (..10)).should == false
      end

      it "returns false if self is finite and other is beginless and they overlap" do
        (0..10).send(@method, ...10).should == false
      end

      it "returns false if self is finite and other is endless and they overlap" do
        (0..10).send(@method, 0..).should == false
      end
    end

    context "when other range does not interleave" do
      it "returns false if self.begin > other.end" do
        (6..10).send(@method, 0..4).should == false
      end

      it "returns false if self.end < other.begin" do
        (0..4).send(@method, 6..10).should == false
      end

      it "returns false if self is beginless but self.end < other.begin" do
        (...4).send(@method, 6..10).should == false
      end

      it "returns false if self is beginless and self.end == other.begin but self.exclude_end? is true" do
        (...4).send(@method, 4..10).should == false
      end

      it "returns false if self is beginless and other is endless but self.end < other.begin" do
        (...0).send(@method, (10..)).should == false
      end

      it "returns false if self is beginless and other is endless and self.end == other.begin but self.exclude_end? is true" do
        (...10).send(@method, (10..)).should == false
      end

      it "returns false if self is endless but self.begin > other.end" do
        (10..).send(@method, 0..6).should == false
      end

      it "returns false if self is endless but self.begin == other.end but other.exclude_end? is true" do
        (6..).send(@method, (0...6)).should == false
      end

      it "returns false if other is beginless but self.begin > other.end" do
        (4..10).send(@method, (...0)).should == false
      end

      it "returns false if other is beginless and self.begin == other.end but other.exclude_end? is true" do
        (6..10).send(@method, (...6)).should == false
      end

      it "returns false if other is beginless and self is endless and other.end == self.begin but other.exclude_end? is true" do
        (10..).send(@method, (...10)).should == false
      end

      it "returns false if other is endless but self.end < other.begin" do
        (0..4).send(@method, (10..)).should == false
      end

      it "returns false if other is endless and self.end == other.begin but self.exclude_end? is true" do
        (0...10).send(@method, (10..)).should == false
      end
    end

    context "when comparing with backward ranges" do
      it "returns false if other is backward and fits into self" do
        (0..10).send(@method, 6..4).should == false
      end

      it "returns false if self is backward and other fits into self" do
        (10..0).send(@method, 4..6).should == false
      end
    end

    context "when comparing with empty ranges" do
      it "returns false if other is empty and fits into self" do
        (0..10).send(@method, 4...4).should == false
      end

      it "returns false if self is empty and equals other" do
        (0...0).send(@method, 0...0).should == false
      end
    end

    it "returns false if other boundaries are not comparable with self boundaries" do
      (0..10).send(@method, ("a".."z")).should == false
    end
  end

  context "range argument with boundaries of generic type (that implements only #<=>)" do
    context "when other range is completely inside self" do
      context "when a range can be iterated (that's it responds to #succ)" do
        it "returns true if self.begin < other.begin and self.end < other.end but other.exclude_end? is true and the rightmost other value <= self.end" do
          a = RangeSpecs::CoverElementWithSucc.new(0)..RangeSpecs::CoverElementWithSucc.new(10)
          b = RangeSpecs::CoverElementWithSucc.new(4)...RangeSpecs::CoverElementWithSucc.new(11)
          (a).send(@method, b).should == true
        end

        it "returns true if self is beginless and self.end < other.end but other.exclude_end? is true and the rightmost other value <= self.end" do
          a = ..RangeSpecs::CoverElementWithSucc.new(10)
          b = RangeSpecs::CoverElementWithSucc.new(4)...RangeSpecs::CoverElementWithSucc.new(11)
          (a).send(@method, b).should == true
        end
      end
    end

    context "when other range is partially interleaved" do
      context "when a range cannot be iterated (that's it does not responds to #succ)" do
        it "returns false if self.begin < other.begin, self.end < other.end but other.exclude_end? is true and the rightmost other value < self.end" do
          (0..10.0).send(@method, 5...11.0).should == false
        end

        it "returns false if self is beginless and self.end < other.end but other.exclude_end? is true and the rightmost other value < self.end" do
          (..10.0).send(@method, ...11.0).should == false
        end
      end
    end
  end
end
