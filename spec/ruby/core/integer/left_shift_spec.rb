require_relative '../../spec_helper'

describe "Integer#<< (with n << m)" do
  context "fixnum" do
    it "returns n shifted left m bits when n > 0, m > 0" do
      (1 << 1).should == 2
    end

    it "returns n shifted left m bits when n < 0, m > 0" do
      (-1 << 1).should == -2
      (-7 << 1).should == -14
      (-42 << 2).should == -168
    end

    it "returns n shifted right m bits when n > 0, m < 0" do
      (2 << -1).should == 1
    end

    it "returns n shifted right m bits when n < 0, m < 0" do
      (-2 << -1).should == -1
    end

    it "returns 0 when n == 0" do
      (0 << 1).should == 0
    end

    it "returns n when n > 0, m == 0" do
      (1 << 0).should == 1
    end

    it "returns n when n < 0, m == 0" do
      (-1 << 0).should == -1
    end

    it "returns 0 when n > 0, m < 0 and n < 2**-m" do
      (3 << -2).should == 0
      (7 << -3).should == 0
      (127 << -7).should == 0

      # To make sure the exponent is not truncated
      (7 << -32).should == 0
      (7 << -64).should == 0
    end

    it "returns -1 when n < 0, m < 0 and n > -(2**-m)" do
      (-3 << -2).should == -1
      (-7 << -3).should == -1
      (-127 << -7).should == -1

      # To make sure the exponent is not truncated
      (-7 << -32).should == -1
      (-7 << -64).should == -1
    end

    it "returns 0 when m < 0 and m is a Bignum" do
      (3 << -bignum_value).should == 0
    end

    it "returns an Bignum == fixnum_max * 2 when fixnum_max << 1 and n > 0" do
      result = fixnum_max << 1
      result.should be_an_instance_of(Bignum)
      result.should == fixnum_max * 2
    end

    it "returns an Bignum == fixnum_min * 2 when fixnum_min << 1 and n < 0" do
      result = fixnum_min << 1
      result.should be_an_instance_of(Bignum)
      result.should == fixnum_min * 2
    end

    it "calls #to_int to convert the argument to an Integer" do
      obj = mock("4")
      obj.should_receive(:to_int).and_return(4)

      (3 << obj).should == 48
    end

    it "raises a TypeError when #to_int does not return an Integer" do
      obj = mock("a string")
      obj.should_receive(:to_int).and_return("asdf")

      -> { 3 << obj }.should raise_error(TypeError)
    end

    it "raises a TypeError when passed nil" do
      -> { 3 << nil }.should raise_error(TypeError)
    end

    it "raises a TypeError when passed a String" do
      -> { 3 << "4" }.should raise_error(TypeError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value * 16
    end

    it "returns n shifted left m bits when n > 0, m > 0" do
      (@bignum << 4).should == 2361183241434822606848
    end

    it "returns n shifted left m bits when n < 0, m > 0" do
      (-@bignum << 9).should == -75557863725914323419136
    end

    it "returns n shifted right m bits when n > 0, m < 0" do
      (@bignum << -1).should == 73786976294838206464
    end

    it "returns n shifted right m bits when n < 0, m < 0" do
      (-@bignum << -2).should == -36893488147419103232
    end

    it "returns n when n > 0, m == 0" do
      (@bignum << 0).should == @bignum
    end

    it "returns n when n < 0, m == 0" do
      (-@bignum << 0).should == -@bignum
    end

    it "returns 0 when m < 0 and m == p where 2**p > n >= 2**(p-1)" do
      (@bignum << -68).should == 0
    end

    it "returns 0 when m < 0 and m is a Bignum" do
      (@bignum << -bignum_value).should == 0
    end

    it "returns a Fixnum == fixnum_max when (fixnum_max * 2) << -1 and n > 0" do
      result = (fixnum_max * 2) << -1
      result.should be_an_instance_of(Fixnum)
      result.should == fixnum_max
    end

    it "returns a Fixnum == fixnum_min when (fixnum_min * 2) << -1 and n < 0" do
      result = (fixnum_min * 2) << -1
      result.should be_an_instance_of(Fixnum)
      result.should == fixnum_min
    end

    it "calls #to_int to convert the argument to an Integer" do
      obj = mock("4")
      obj.should_receive(:to_int).and_return(4)

      (@bignum << obj).should == 2361183241434822606848
    end

    it "raises a TypeError when #to_int does not return an Integer" do
      obj = mock("a string")
      obj.should_receive(:to_int).and_return("asdf")

      -> { @bignum << obj }.should raise_error(TypeError)
    end

    it "raises a TypeError when passed nil" do
      -> { @bignum << nil }.should raise_error(TypeError)
    end

    it "raises a TypeError when passed a String" do
      -> { @bignum << "4" }.should raise_error(TypeError)
    end
  end
end
