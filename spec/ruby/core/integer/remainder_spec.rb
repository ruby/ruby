require_relative '../../spec_helper'

describe "Integer#remainder" do
  context "fixnum" do
    it "returns the remainder of dividing self by other" do
      5.remainder(3).should == 2
      5.remainder(3.0).should == 2.0
      5.remainder(Rational(3, 1)).should == Rational(2, 1)
    end

    it "means x-y*(x/y).truncate" do
      5.remainder(3).should == 2
      5.remainder(3.3).should be_close(1.7, TOLERANCE)
      5.remainder(3.7).should be_close(1.3, TOLERANCE)
    end

    it "keeps sign of self" do
       5.remainder( 3).should ==  2
       5.remainder(-3).should ==  2
      -5.remainder( 3).should == -2
      -5.remainder(-3).should == -2
    end

    it "raises TypeError if passed non-numeric argument" do
      -> { 5.remainder("3") }.should raise_error(TypeError)
      -> { 5.remainder(:"3") }.should raise_error(TypeError)
      -> { 5.remainder([]) }.should raise_error(TypeError)
      -> { 5.remainder(nil) }.should raise_error(TypeError)
    end
  end

  context "bignum" do
    it "returns the remainder of dividing self by other" do
      a = bignum_value(79)
      a.remainder(2).should == 1
      a.remainder(97.345).should be_close(46.5674996147722, TOLERANCE)
      a.remainder(bignum_value).should == 79
    end

    it "raises a ZeroDivisionError if other is zero and not a Float" do
      -> { bignum_value(66).remainder(0) }.should raise_error(ZeroDivisionError)
    end

    it "does raises ZeroDivisionError if other is zero and a Float" do
      a = bignum_value(7)
      b = bignum_value(32)
      -> { a.remainder(0.0) }.should raise_error(ZeroDivisionError)
      -> { b.remainder(-0.0) }.should raise_error(ZeroDivisionError)
    end
  end
end
