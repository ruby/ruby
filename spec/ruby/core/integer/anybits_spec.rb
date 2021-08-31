require_relative '../../spec_helper'

describe "Integer#anybits?" do
  it "returns true if and only if all the bits of the argument are set in the receiver" do
    42.anybits?(42).should == true
    0b1010_1010.anybits?(0b1000_0010).should == true
    0b1010_1010.anybits?(0b1000_0001).should == true
    0b1000_0010.anybits?(0b0010_1100).should == false
    different_bignum = (2 * bignum_value) & (~bignum_value)
    (0b1010_1010 | different_bignum).anybits?(0b1000_0010 | bignum_value).should == true
    (0b1010_1010 | different_bignum).anybits?(0b0010_1100 | bignum_value).should == true
    (0b1000_0010 | different_bignum).anybits?(0b0010_1100 | bignum_value).should == false
  end

  it "handles negative values using two's complement notation" do
    (~42).anybits?(42).should == false
    (-42).anybits?(-42).should == true
    (~0b100).anybits?(~0b1).should == true
    (~(0b100 | bignum_value)).anybits?(~(0b1 | bignum_value)).should == true
  end

  it "coerces the rhs using to_int" do
    obj = mock("the int 0b10")
    obj.should_receive(:to_int).and_return(0b10)
    0b110.anybits?(obj).should == true
  end

  it "raises a TypeError when given a non-Integer" do
    -> {
      (obj = mock('10')).should_receive(:coerce).any_number_of_times.and_return([42,10])
      13.anybits?(obj)
    }.should raise_error(TypeError)
    -> { 13.anybits?("10")    }.should raise_error(TypeError)
    -> { 13.anybits?(:symbol) }.should raise_error(TypeError)
  end
end
