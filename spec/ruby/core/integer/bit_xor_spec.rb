require_relative '../../spec_helper'

describe "Integer#^" do
  context "fixnum" do
    it "returns self bitwise EXCLUSIVE OR other" do
      (3 ^ 5).should == 6
      (-2 ^ -255).should == 255
      (5 ^ bignum_value + 0xffff_ffff).should == 0x1_0000_0000_ffff_fffa
    end

    it "returns self bitwise XOR other when one operand is negative" do
      ((1 << 33) ^ -1).should == -8589934593
      (-1 ^ (1 << 33)).should == -8589934593

      ((-(1<<33)-1) ^ 5).should == -8589934598
      (5 ^ (-(1<<33)-1)).should == -8589934598
    end

    it "returns self bitwise XOR other when both operands are negative" do
      (-5 ^ -1).should == 4
      (-3 ^ -4).should == 1
      (-12 ^ -13).should == 7
      (-13 ^ -12).should == 7
    end

    it "returns self bitwise EXCLUSIVE OR a bignum" do
      (-1 ^ 2**64).should == -18446744073709551617
    end

    it "coerces the rhs and calls #coerce" do
      obj = mock("fixnum bit xor")
      obj.should_receive(:coerce).with(6).and_return([6, 3])
      (6 ^ obj).should == 5
    end

    it "raises a TypeError when passed a Float" do
      -> { (3 ^ 3.4) }.should raise_error(TypeError)
    end

    it "raises a TypeError and does not call #to_int when defined on an object" do
      obj = mock("integer bit xor")
      obj.should_not_receive(:to_int)

      -> { 3 ^ obj }.should raise_error(TypeError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(18)
    end

    it "returns self bitwise EXCLUSIVE OR other" do
      (@bignum ^ 2).should == 18446744073709551632
      (@bignum ^ @bignum).should == 0
      (@bignum ^ 14).should == 18446744073709551644
    end

    it "returns self bitwise EXCLUSIVE OR other when one operand is negative" do
      (@bignum ^ -0x40000000000000000).should == -55340232221128654830
      (@bignum ^ -@bignum).should == -4
      (@bignum ^ -0x8000000000000000).should == -27670116110564327406
    end

    it "returns self bitwise EXCLUSIVE OR other when both operands are negative" do
      (-@bignum ^ -0x40000000000000000).should == 55340232221128654830
      (-@bignum ^ -@bignum).should == 0
      (-@bignum ^ -0x4000000000000000).should == 23058430092136939502
    end

    it "returns self bitwise EXCLUSIVE OR other when all bits are 1 and other value is negative" do
      (9903520314283042199192993791 ^ -1).should == -9903520314283042199192993792
      (784637716923335095479473677900958302012794430558004314111 ^ -1).should ==
        -784637716923335095479473677900958302012794430558004314112
    end

    it "raises a TypeError when passed a Float" do
      not_supported_on :opal do
        -> {
          bignum_value ^ bignum_value(0xffff).to_f
        }.should raise_error(TypeError)
      end
      -> { @bignum ^ 14.5 }.should raise_error(TypeError)
    end

    it "raises a TypeError and does not call #to_int when defined on an object" do
      obj = mock("bignum bit xor")
      obj.should_not_receive(:to_int)

      -> { @bignum ^ obj }.should raise_error(TypeError)
    end
  end
end
