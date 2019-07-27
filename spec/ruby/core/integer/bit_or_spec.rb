require_relative '../../spec_helper'

describe "Integer#|" do
  context "fixnum" do
    it "returns self bitwise OR other" do
      (1 | 0).should == 1
      (5 | 4).should == 5
      (5 | 6).should == 7
      (248 | 4096).should == 4344
      (0xffff | bignum_value + 0xf0f0).should == 0x8000_0000_0000_ffff
    end

    it "returns self bitwise OR a bignum" do
      (-1 | 2**64).should == -1
    end

    it "raises a TypeError when passed a Float" do
      -> { (3 | 3.4) }.should raise_error(TypeError)
    end

    it "raises a TypeError and does not call #to_int when defined on an object" do
      obj = mock("integer bit or")
      obj.should_not_receive(:to_int)

      -> { 3 | obj }.should raise_error(TypeError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(11)
    end

    it "returns self bitwise OR other" do
      (@bignum | 2).should == 9223372036854775819
      (@bignum | 9).should == 9223372036854775819
      (@bignum | bignum_value).should == 9223372036854775819
    end

    it "returns self bitwise OR other when one operand is negative" do
      (@bignum | -0x40000000000000000).should == -64563604257983430645
      (@bignum | -@bignum).should == -1
      (@bignum | -0x8000000000000000).should == -9223372036854775797
    end

    it "returns self bitwise OR other when both operands are negative" do
      (-@bignum | -0x4000000000000005).should == -1
      (-@bignum | -@bignum).should == -9223372036854775819
      (-@bignum | -0x4000000000000000).should == -11
    end

    it "raises a TypeError when passed a Float" do
      not_supported_on :opal do
        -> {
          bignum_value | bignum_value(0xffff).to_f
        }.should raise_error(TypeError)
      end
      -> { @bignum | 9.9 }.should raise_error(TypeError)
    end

    it "raises a TypeError and does not call #to_int when defined on an object" do
      obj = mock("bignum bit or")
      obj.should_not_receive(:to_int)

      -> { @bignum | obj }.should raise_error(TypeError)
    end
  end
end
