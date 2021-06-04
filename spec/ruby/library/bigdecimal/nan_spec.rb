require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal#nan?" do

  it "returns true if self is not a number" do
    BigDecimal("NaN").should.nan?
  end

  it "returns false if self is not a NaN" do
    BigDecimal("Infinity").should_not.nan?
    BigDecimal("-Infinity").should_not.nan?
    BigDecimal("0").should_not.nan?
    BigDecimal("+0").should_not.nan?
    BigDecimal("-0").should_not.nan?
    BigDecimal("2E40001").should_not.nan?
    BigDecimal("3E-20001").should_not.nan?
    BigDecimal("0E-200000000").should_not.nan?
    BigDecimal("0E200000000000").should_not.nan?
    BigDecimal("0.000000000000000000000000").should_not.nan?
  end

end
