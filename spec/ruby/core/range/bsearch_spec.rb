require_relative '../../spec_helper'
require_relative '../enumerable/shared/enumeratorized'

describe "Range#bsearch" do
  it "returns an Enumerator when not passed a block" do
    (0..1).bsearch.should be_an_instance_of(Enumerator)
  end

  it_behaves_like :enumeratorized_with_unknown_size, :bsearch, (1..3)

  it "raises a TypeError if the block returns an Object" do
    -> { (0..1).bsearch { Object.new } }.should raise_error(TypeError)
  end

  it "raises a TypeError if the block returns a String" do
    -> { (0..1).bsearch { "1" } }.should raise_error(TypeError)
  end

  it "raises a TypeError if the Range has Object values" do
    value = mock("range bsearch")
    r = Range.new value, value

    -> { r.bsearch { true } }.should raise_error(TypeError)
  end

  it "raises a TypeError if the Range has String values" do
    -> { ("a".."e").bsearch { true } }.should raise_error(TypeError)
  end

  context "with Integer values" do
    context "with a block returning true or false" do
      it "returns nil if the block returns false for every element" do
        (0...3).bsearch { |x| x > 3 }.should be_nil
      end

      it "returns nil if the block returns nil for every element" do
        (0..3).bsearch { |x| nil }.should be_nil
      end

      it "returns minimum element if the block returns true for every element" do
        (-2..4).bsearch { |x| x < 4 }.should == -2
      end

      it "returns the smallest element for which block returns true" do
        (0..4).bsearch { |x| x >= 2 }.should == 2
        (-1..4).bsearch { |x| x >= 1 }.should == 1
      end

      it "returns the last element if the block returns true for the last element" do
        (0..4).bsearch { |x| x >= 4 }.should == 4
        (0...4).bsearch { |x| x >= 3 }.should == 3
      end
    end

    context "with a block returning negative, zero, positive numbers" do
      it "returns nil if the block returns less than zero for every element" do
        (0..3).bsearch { |x| x <=> 5 }.should be_nil
      end

      it "returns nil if the block returns greater than zero for every element" do
        (0..3).bsearch { |x| x <=> -1 }.should be_nil

      end

      it "returns nil if the block never returns zero" do
        (0..3).bsearch { |x| x < 2 ? 1 : -1 }.should be_nil
      end

      it "accepts (+/-)Float::INFINITY from the block" do
        (0..4).bsearch { |x| Float::INFINITY }.should be_nil
        (0..4).bsearch { |x| -Float::INFINITY }.should be_nil
      end

      it "returns an element at an index for which block returns 0.0" do
        result = (0..4).bsearch { |x| x < 2 ? 1.0 : x > 2 ? -1.0 : 0.0 }
        result.should == 2
      end

      it "returns an element at an index for which block returns 0" do
        result = (0..4).bsearch { |x| x < 1 ? 1 : x > 3 ? -1 : 0 }
        [1, 2].should include(result)
      end
    end

    it "returns nil for empty ranges" do
      (0...0).bsearch { true }.should == nil
      (0...0).bsearch { false }.should == nil
      (0...0).bsearch { 1 }.should == nil
      (0...0).bsearch { 0 }.should == nil
      (0...0).bsearch { -1 }.should == nil

      (4..2).bsearch { true }.should == nil
      (4..2).bsearch { 1 }.should == nil
      (4..2).bsearch { 0 }.should == nil
      (4..2).bsearch { -1 }.should == nil
    end
  end

  context "with Float values" do
    context "with a block returning true or false" do
      it "returns nil if the block returns false for every element" do
        (0.1...2.3).bsearch { |x| x > 3 }.should be_nil
      end

      it "returns nil if the block returns nil for every element" do
        (-0.0..2.3).bsearch { |x| nil }.should be_nil
      end

      it "returns minimum element if the block returns true for every element" do
        (-0.2..4.8).bsearch { |x| x < 5 }.should == -0.2
      end

      it "returns the smallest element for which block returns true" do
        (0..4.2).bsearch { |x| x >= 2 }.should == 2
        (-1.2..4.3).bsearch { |x| x >= 1 }.should == 1
      end

      it "returns a boundary element if appropriate" do
        (1.0..3.0).bsearch { |x| x >= 3.0 }.should == 3.0
        (1.0...3.0).bsearch { |x| x >= 3.0.prev_float }.should == 3.0.prev_float
        (1.0..3.0).bsearch { |x| x >= 1.0 }.should == 1.0
        (1.0...3.0).bsearch { |x| x >= 1.0 }.should == 1.0
      end

      it "works with infinity bounds" do
        inf = Float::INFINITY
        (0..inf).bsearch { |x| x == inf }.should == inf
        (0...inf).bsearch { |x| x == inf }.should == nil
        (-inf..0).bsearch { |x| x != -inf }.should == -Float::MAX
        (-inf...0).bsearch { |x| x != -inf }.should == -Float::MAX
        (inf..inf).bsearch { |x| true }.should == inf
        (inf...inf).bsearch { |x| true }.should == nil
        (-inf..-inf).bsearch { |x| true }.should == -inf
        (-inf...-inf).bsearch { |x| true }.should == nil
        (inf..0).bsearch { true }.should == nil
        (inf...0).bsearch { true }.should == nil
        (0..-inf).bsearch { true }.should == nil
        (0...-inf).bsearch { true }.should == nil
        (inf..-inf).bsearch { true }.should == nil
        (inf...-inf).bsearch { true }.should == nil
        (0..inf).bsearch { |x| x >= 3 }.should == 3.0
        (0...inf).bsearch { |x| x >= 3 }.should == 3.0
        (-inf..0).bsearch { |x| x >= -3 }.should == -3.0
        (-inf...0).bsearch { |x| x >= -3 }.should == -3.0
        (-inf..inf).bsearch { |x| x >= 3 }.should == 3.0
        (-inf...inf).bsearch { |x| x >= 3 }.should == 3.0
        (0..inf).bsearch { |x| x >= Float::MAX }.should == Float::MAX
        (0...inf).bsearch { |x| x >= Float::MAX }.should == Float::MAX
      end
    end

    context "with a block returning negative, zero, positive numbers" do
      it "returns nil if the block returns less than zero for every element" do
        (-2.0..3.2).bsearch { |x| x <=> 5 }.should be_nil
      end

      it "returns nil if the block returns greater than zero for every element" do
        (0.3..3.0).bsearch { |x| x <=> -1 }.should be_nil

      end

      it "returns nil if the block never returns zero" do
        (0.2..2.3).bsearch { |x| x < 2 ? 1 : -1 }.should be_nil
      end

      it "accepts (+/-)Float::INFINITY from the block" do
        (0.1..4.5).bsearch { |x| Float::INFINITY }.should be_nil
        (-5.0..4.0).bsearch { |x| -Float::INFINITY }.should be_nil
      end

      it "returns an element at an index for which block returns 0.0" do
        result = (0.0..4.0).bsearch { |x| x < 2 ? 1.0 : x > 2 ? -1.0 : 0.0 }
        result.should == 2
      end

      it "returns an element at an index for which block returns 0" do
        result = (0.1..4.9).bsearch { |x| x < 1 ? 1 : x > 3 ? -1 : 0 }
        result.should >= 1
        result.should <= 3
      end

      it "returns an element at an index for which block returns 0 (small numbers)" do
        result = (0.1..0.3).bsearch { |x| x < 0.1 ? 1 : x > 0.3 ? -1 : 0 }
        result.should >= 0.1
        result.should <= 0.3
      end

      it "returns a boundary element if appropriate" do
        (1.0..3.0).bsearch { |x| 3.0 - x }.should == 3.0
        (1.0...3.0).bsearch { |x| 3.0.prev_float - x }.should == 3.0.prev_float
        (1.0..3.0).bsearch { |x| 1.0 - x }.should == 1.0
        (1.0...3.0).bsearch { |x| 1.0 - x }.should == 1.0
      end

      it "works with infinity bounds" do
        inf = Float::INFINITY
        (0..inf).bsearch { |x| x == inf ? 0 : 1 }.should == inf
        (0...inf).bsearch { |x| x == inf ? 0 : 1 }.should == nil
        (-inf...0).bsearch { |x| x == -inf ? 0 : -1 }.should == -inf
        (-inf..0).bsearch { |x| x == -inf ? 0 : -1 }.should == -inf
        (inf..inf).bsearch { 0 }.should == inf
        (inf...inf).bsearch { 0 }.should == nil
        (-inf..-inf).bsearch { 0 }.should == -inf
        (-inf...-inf).bsearch { 0 }.should == nil
        (inf..0).bsearch { 0 }.should == nil
        (inf...0).bsearch { 0 }.should == nil
        (0..-inf).bsearch { 0 }.should == nil
        (0...-inf).bsearch { 0 }.should == nil
        (inf..-inf).bsearch { 0 }.should == nil
        (inf...-inf).bsearch { 0 }.should == nil
        (-inf..inf).bsearch { |x| 3 - x }.should == 3.0
        (-inf...inf).bsearch { |x| 3 - x }.should == 3.0
        (0...inf).bsearch { |x| x >= Float::MAX ? 0 : 1 }.should == Float::MAX
      end
    end
  end

  context "with endless ranges and Integer values" do
    context "with a block returning true or false" do
      it "returns minimum element if the block returns true for every element" do
        eval("(-2..)").bsearch { |x| true }.should == -2
      end

      it "returns the smallest element for which block returns true" do
        eval("(0..)").bsearch { |x| x >= 2 }.should == 2
        eval("(-1..)").bsearch { |x| x >= 1 }.should == 1
      end
    end

    context "with a block returning negative, zero, positive numbers" do
      it "returns nil if the block returns less than zero for every element" do
        eval("(0..)").bsearch { |x| -1 }.should be_nil
      end

      it "returns nil if the block never returns zero" do
        eval("(0..)").bsearch { |x| x > 5 ? -1 : 1 }.should be_nil
      end

      it "accepts -Float::INFINITY from the block" do
        eval("(0..)").bsearch { |x| -Float::INFINITY }.should be_nil
      end

      it "returns an element at an index for which block returns 0.0" do
        result = eval("(0..)").bsearch { |x| x < 2 ? 1.0 : x > 2 ? -1.0 : 0.0 }
        result.should == 2
      end

      it "returns an element at an index for which block returns 0" do
        result = eval("(0..)").bsearch { |x| x < 1 ? 1 : x > 3 ? -1 : 0 }
        [1, 2, 3].should include(result)
      end
    end
  end

  context "with endless ranges and Float values" do
    context "with a block returning true or false" do
      it "returns nil if the block returns false for every element" do
        eval("(0.1..)").bsearch { |x| x < 0.0 }.should be_nil
        eval("(0.1...)").bsearch { |x| x < 0.0 }.should be_nil
      end

      it "returns nil if the block returns nil for every element" do
        eval("(-0.0..)").bsearch { |x| nil }.should be_nil
        eval("(-0.0...)").bsearch { |x| nil }.should be_nil
      end

      it "returns minimum element if the block returns true for every element" do
        eval("(-0.2..)").bsearch { |x| true }.should == -0.2
        eval("(-0.2...)").bsearch { |x| true }.should == -0.2
      end

      it "returns the smallest element for which block returns true" do
        eval("(0..)").bsearch { |x| x >= 2 }.should == 2
        eval("(-1.2..)").bsearch { |x| x >= 1 }.should == 1
      end

      it "works with infinity bounds" do
        inf = Float::INFINITY
        eval("(inf..)").bsearch { |x| true }.should == inf
        eval("(inf...)").bsearch { |x| true }.should == nil
        eval("(-inf..)").bsearch { |x| true }.should == -inf
        eval("(-inf...)").bsearch { |x| true }.should == -inf
      end
    end

    context "with a block returning negative, zero, positive numbers" do
      it "returns nil if the block returns less than zero for every element" do
        eval("(-2.0..)").bsearch { |x| -1 }.should be_nil
        eval("(-2.0...)").bsearch { |x| -1 }.should be_nil
      end

      it "returns nil if the block returns greater than zero for every element" do
        eval("(0.3..)").bsearch { |x| 1 }.should be_nil
        eval("(0.3...)").bsearch { |x| 1 }.should be_nil
      end

      it "returns nil if the block never returns zero" do
        eval("(0.2..)").bsearch { |x| x < 2 ? 1 : -1 }.should be_nil
      end

      it "accepts (+/-)Float::INFINITY from the block" do
        eval("(0.1..)").bsearch { |x| Float::INFINITY }.should be_nil
        eval("(-5.0..)").bsearch { |x| -Float::INFINITY }.should be_nil
      end

      it "returns an element at an index for which block returns 0.0" do
        result = eval("(0.0..)").bsearch { |x| x < 2 ? 1.0 : x > 2 ? -1.0 : 0.0 }
        result.should == 2
      end

      it "returns an element at an index for which block returns 0" do
        result = eval("(0.1..)").bsearch { |x| x < 1 ? 1 : x > 3 ? -1 : 0 }
        result.should >= 1
        result.should <= 3
      end

      it "works with infinity bounds" do
        inf = Float::INFINITY
        eval("(inf..)").bsearch { |x| 1 }.should == nil
        eval("(inf...)").bsearch { |x| 1 }.should == nil
        eval("(inf..)").bsearch { |x| x == inf ? 0 : 1 }.should == inf
        eval("(inf...)").bsearch { |x| x == inf ? 0 : 1 }.should == nil
        eval("(-inf..)").bsearch { |x| x == -inf ? 0 : -1 }.should == -inf
        eval("(-inf...)").bsearch { |x| x == -inf ? 0 : -1 }.should == -inf
        eval("(-inf..)").bsearch { |x| 3 - x }.should == 3
        eval("(-inf...)").bsearch { |x| 3 - x }.should == 3
        eval("(0.0...)").bsearch { 0 }.should != inf
      end
    end
  end


  context "with beginless ranges and Integer values" do
    context "with a block returning true or false" do
      it "returns the smallest element for which block returns true" do
        (..10).bsearch { |x| x >= 2 }.should == 2
        (...-1).bsearch { |x| x >= -10 }.should == -10
      end
    end

    context "with a block returning negative, zero, positive numbers" do
      it "returns nil if the block returns greater than zero for every element" do
        (..0).bsearch { |x| 1 }.should be_nil
      end

      it "returns nil if the block never returns zero" do
        (..0).bsearch { |x| x > 5 ? -1 : 1 }.should be_nil
      end

      it "accepts Float::INFINITY from the block" do
        (..0).bsearch { |x| Float::INFINITY }.should be_nil
      end

      it "returns an element at an index for which block returns 0.0" do
        result = (..10).bsearch { |x| x < 2 ? 1.0 : x > 2 ? -1.0 : 0.0 }
        result.should == 2
      end

      it "returns an element at an index for which block returns 0" do
        result = (...10).bsearch { |x| x < 1 ? 1 : x > 3 ? -1 : 0 }
        [1, 2, 3].should include(result)
      end
    end
  end

  context "with beginless ranges and Float values" do
    context "with a block returning true or false" do
      it "returns nil if the block returns true for every element" do
        (..-0.1).bsearch { |x| x > 0.0 }.should be_nil
        (...-0.1).bsearch { |x| x > 0.0 }.should be_nil
      end

      it "returns nil if the block returns nil for every element" do
        (..-0.1).bsearch { |x| nil }.should be_nil
        (...-0.1).bsearch { |x| nil }.should be_nil
      end

      it "returns the smallest element for which block returns true" do
        (..10).bsearch { |x| x >= 2 }.should == 2
        (..10).bsearch { |x| x >= 1 }.should == 1
      end

      it "works with infinity bounds" do
        inf = Float::INFINITY
        (..inf).bsearch { |x| true }.should == -inf
        (...inf).bsearch { |x| true }.should == -inf
        (..-inf).bsearch { |x| true }.should == -inf
        (...-inf).bsearch { |x| true }.should == nil
      end
    end

    context "with a block returning negative, zero, positive numbers" do
      it "returns nil if the block returns less than zero for every element" do
        (..5.0).bsearch { |x| -1 }.should be_nil
        (...5.0).bsearch { |x| -1 }.should be_nil
      end

      it "returns nil if the block returns greater than zero for every element" do
        (..1.1).bsearch { |x| 1 }.should be_nil
        (...1.1).bsearch { |x| 1 }.should be_nil
      end

      it "returns nil if the block never returns zero" do
        (..6.3).bsearch { |x| x < 2 ? 1 : -1 }.should be_nil
      end

      it "accepts (+/-)Float::INFINITY from the block" do
        (..5.0).bsearch { |x| Float::INFINITY }.should be_nil
        (..7.0).bsearch { |x| -Float::INFINITY }.should be_nil
      end

      it "returns an element at an index for which block returns 0.0" do
        result = (..8.0).bsearch { |x| x < 2 ? 1.0 : x > 2 ? -1.0 : 0.0 }
        result.should == 2
      end

      it "returns an element at an index for which block returns 0" do
        result = (..8.0).bsearch { |x| x < 1 ? 1 : x > 3 ? -1 : 0 }
        result.should >= 1
        result.should <= 3
      end

      it "works with infinity bounds" do
        inf = Float::INFINITY
        (..-inf).bsearch { |x| 1 }.should == nil
        (...-inf).bsearch { |x| 1 }.should == nil
        (..inf).bsearch { |x| x == inf ? 0 : 1 }.should == inf
        (...inf).bsearch { |x| x == inf ? 0 : 1 }.should == nil
        (..-inf).bsearch { |x| x == -inf ? 0 : -1 }.should == -inf
        (...-inf).bsearch { |x| x == -inf ? 0 : -1 }.should == nil
        (..inf).bsearch { |x| 3 - x }.should == 3
        (...inf).bsearch { |x| 3 - x }.should == 3
      end
    end
  end
end
