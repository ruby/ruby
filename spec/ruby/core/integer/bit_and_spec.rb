require_relative '../../spec_helper'

describe "Integer#&" do
  context "fixnum" do
    it "returns self bitwise AND other" do
      (256 & 16).should == 0
      (2010 & 5).should == 0
      (65535 & 1).should == 1
      (0xffff & bignum_value + 0xffff_ffff).should == 65535
    end

    it "returns self bitwise AND other when one operand is negative" do
      ((1 << 33) & -1).should == (1 << 33)
      (-1 & (1 << 33)).should == (1 << 33)

      ((-(1<<33)-1) & 5).should == 5
      (5 & (-(1<<33)-1)).should == 5
    end

    it "returns self bitwise AND other when both operands are negative" do
      (-5 & -1).should == -5
      (-3 & -4).should == -4
      (-12 & -13).should == -16
      (-13 & -12).should == -16
    end

    it "returns self bitwise AND a bignum" do
      (-1 & 2**64).should == 18446744073709551616
    end

    it "coerces the rhs and calls #coerce" do
      obj = mock("fixnum bit and")
      obj.should_receive(:coerce).with(6).and_return([3, 6])
      (6 & obj).should == 2
    end

    it "raises a TypeError when passed a Float" do
      -> { (3 & 3.4) }.should raise_error(TypeError)
    end

    it "raises a TypeError and does not call #to_int when defined on an object" do
      obj = mock("fixnum bit and")
      obj.should_not_receive(:to_int)

      -> { 3 & obj }.should raise_error(TypeError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(5)
    end

    it "returns self bitwise AND other" do
      @bignum = bignum_value(5)
      (@bignum & 3).should == 1
      (@bignum & 52).should == 4
      (@bignum & bignum_value(9921)).should == 9223372036854775809

      ((2*bignum_value) & 1).should == 0
      ((2*bignum_value) & (2*bignum_value)).should == 18446744073709551616
    end

    it "returns self bitwise AND other when one operand is negative" do
      ((2*bignum_value) & -1).should == (2*bignum_value)
      ((4*bignum_value) & -1).should == (4*bignum_value)
      (@bignum & -0xffffffffffffff5).should == 9223372036854775809
      (@bignum & -@bignum).should == 1
      (@bignum & -0x8000000000000000).should == 9223372036854775808
    end

    it "returns self bitwise AND other when both operands are negative" do
      (-@bignum & -0x4000000000000005).should == -13835058055282163717
      (-@bignum & -@bignum).should == -9223372036854775813
      (-@bignum & -0x4000000000000000).should == -13835058055282163712
    end

    it "returns self bitwise AND other when both are negative and a multiple in bitsize of Fixnum::MIN" do
      val = - ((1 << 93) - 1)
      (val & val).should == val

      val = - ((1 << 126) - 1)
      (val & val).should == val
    end

    it "raises a TypeError when passed a Float" do
      -> { (@bignum & 3.4) }.should raise_error(TypeError)
    end

    it "raises a TypeError and does not call #to_int when defined on an object" do
      obj = mock("bignum bit and")
      obj.should_not_receive(:to_int)

      -> { @bignum & obj }.should raise_error(TypeError)
    end
  end
end
