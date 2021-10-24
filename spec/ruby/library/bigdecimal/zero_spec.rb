require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal#zero?" do

  it "returns true if self does equal zero" do
    really_small_zero = BigDecimal("0E-200000000")
    really_big_zero = BigDecimal("0E200000000000")
    really_small_zero.should.zero?
    really_big_zero.should.zero?
    BigDecimal("0.000000000000000000000000").should.zero?
    BigDecimal("0").should.zero?
    BigDecimal("0E0").should.zero?
    BigDecimal("+0").should.zero?
    BigDecimal("-0").should.zero?
  end

  it "returns false otherwise" do
    BigDecimal("0000000001").should_not.zero?
    BigDecimal("2E40001").should_not.zero?
    BigDecimal("3E-20001").should_not.zero?
    BigDecimal("Infinity").should_not.zero?
    BigDecimal("-Infinity").should_not.zero?
    BigDecimal("NaN").should_not.zero?
  end

end
