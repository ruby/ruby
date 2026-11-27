require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal#precision_scale" do
  it "ignores trailing fractional zeros" do
    BigDecimal("31.0344830").precision_scale.should == [8, 6]
    BigDecimal("1.2300").precision_scale.should == [3, 2]
    BigDecimal("0.0100").precision_scale.should == [2, 2]
    BigDecimal("0.000123400").precision_scale.should == [7, 7]
  end

  it "counts integer and leading fractional zeros" do
    BigDecimal("100.00").precision_scale.should == [3, 0]
    BigDecimal("1E20").precision_scale.should == [21, 0]
    BigDecimal("1E-20").precision_scale.should == [20, 20]
    BigDecimal("0.000").precision_scale.should == [0, 0]
  end
end
