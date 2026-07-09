require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal#to_i" do
  it "raises FloatDomainError if BigDecimal is infinity or NaN" do
    -> { BigDecimal("Infinity").to_i }.should.raise(FloatDomainError)
    -> { BigDecimal("NaN").to_i }.should.raise(FloatDomainError)
  end

  it "returns Integer otherwise" do
    BigDecimal("3E-20001").to_i.should == 0
    BigDecimal("2E4000").to_i.should == 2 * 10 ** 4000
    BigDecimal("2").to_i.should == 2
    BigDecimal("2E10").to_i.should == 20000000000
    BigDecimal("3.14159").to_i.should == 3
  end
end
