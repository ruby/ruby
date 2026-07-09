require_relative '../../spec_helper'

describe "Integer#succ" do
  it "returns the next larger positive Fixnum" do
    2.succ.should == 3
  end

  it "returns the next larger negative Fixnum" do
    (-2).succ.should == -1
  end

  it "returns the next larger positive Bignum" do
    bignum_value.succ.should == bignum_value(1)
  end

  it "returns the next larger negative Bignum" do
    (-bignum_value(1)).succ.should == -bignum_value
  end

  it "overflows a Fixnum to a Bignum" do
    fixnum_max.succ.should == fixnum_max + 1
  end

  it "underflows a Bignum to a Fixnum" do
    (fixnum_min - 1).succ.should == fixnum_min
  end
end
