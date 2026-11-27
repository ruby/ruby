require_relative 'spec_helper'

load_extension("fixnum")

describe "CApiFixnumSpecs" do
  # Must not call FIX2* on other than Fixnum, the result of such case
  # is undefined.

  uint_max = RbConfig::LIMITS["UINT_MAX"]
  int_max = RbConfig::LIMITS["INT_MAX"]
  int_min = RbConfig::LIMITS["INT_MIN"]
  fixnum_int_max = [int_max, fixnum_max].min
  fixnum_int_min = [int_min, fixnum_min].max
  fixnum_uint_max = [uint_max, fixnum_max].min

  before :each do
    @s = CApiFixnumSpecs.new
  end

  describe "FIX2INT" do
    it "converts a Fixnum to a native int" do
      @s.FIX2INT(42).should == 42
      @s.FIX2INT(-14).should == -14
      @s.FIX2INT(-1).should == -1
      @s.FIX2INT(1).should == 1
    end

    it "convert the maximum Fixnum does fit a native int" do
      @s.FIX2INT(fixnum_int_max).should == fixnum_int_max
    end

    it "convert the minimum Fixnum does fit a native int" do
      @s.FIX2INT(fixnum_int_min).should == fixnum_int_min
    end

    guard -> { int_max < fixnum_max } do
      it "raises a RangeError if the value does not fit a native int" do
        -> { @s.FIX2INT(int_max+1) }.should.raise(RangeError)
      end
    end

    guard -> { int_min > fixnum_min } do
      it "raises a RangeError if the value does not fit a native int" do
        -> { @s.FIX2INT(int_min-1) }.should.raise(RangeError)
      end
    end
  end

  describe "FIX2UINT" do
    it "converts a Fixnum" do
      @s.FIX2UINT(0).should == 0
      @s.FIX2UINT(1).should == 1
      @s.FIX2UINT(42).should == 42
    end

    it "convert the maximum Fixnum does fit a native uint" do
      @s.FIX2UINT(fixnum_uint_max).should == fixnum_uint_max
    end

    it "converts a negative number to the complement" do
      @s.FIX2UINT(-1).should == uint_max
      @s.FIX2UINT(fixnum_int_min).should == uint_max - fixnum_int_max
    end

    guard -> { uint_max < fixnum_max } do
      it "raises a RangeError if the value does not fit a native int" do
        -> { @s.FIX2UINT(uint_max+1) }.should.raise(RangeError)
      end
    end
  end
end
