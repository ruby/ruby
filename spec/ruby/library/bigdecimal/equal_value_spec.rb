require_relative '../../spec_helper'
require 'bigdecimal'


describe "BigDecimal#==" do
  before :each do
    @bg6543_21 = BigDecimal("6543.21")
    @bg5667_19 = BigDecimal("5667.19")
    @a = BigDecimal("1.0000000000000000000000000000000000000000005")
    @b = BigDecimal("1.00000000000000000000000000000000000000000005")
    @bigint = BigDecimal("1000.0")
    @nan = BigDecimal("NaN")
    @infinity = BigDecimal("Infinity")
    @infinity_minus = BigDecimal("-Infinity")
  end

  it "tests for equality" do
    (@bg6543_21 == @bg6543_21).should == true
    (@a == @a).should == true
    (@a == @b).should == false
    (@bg6543_21 == @a).should == false
    (@bigint == 1000).should == true
  end

  it "returns false for NaN as it is never equal to any number" do
    (@nan == @nan).should == false
    (@a == @nan).should == false
    (@nan == @a).should == false
    (@nan == @infinity).should == false
    (@nan == @infinity_minus).should == false
    (@infinity == @nan).should == false
    (@infinity_minus == @nan).should == false
  end

  it "returns true for infinity values with the same sign" do
    (@infinity == @infinity).should == true
    (@infinity == BigDecimal("Infinity")).should == true
    (BigDecimal("Infinity") == @infinity).should == true

    (@infinity_minus == @infinity_minus).should == true
    (@infinity_minus == BigDecimal("-Infinity")).should == true
    (BigDecimal("-Infinity") == @infinity_minus).should == true
  end

  it "returns false for infinity values with different signs" do
    (@infinity == @infinity_minus).should == false
    (@infinity_minus == @infinity).should == false
  end

  it "returns false when infinite value compared to finite one" do
    (@infinity == @a).should == false
    (@infinity_minus == @a).should == false

    (@a == @infinity).should == false
    (@a == @infinity_minus).should == false
  end

  it "returns false when compared objects that can not be coerced into BigDecimal" do
    (@infinity == nil).should == false
    (@bigint == nil).should == false
    (@nan == nil).should == false
  end
end
