require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal#to_r" do

  it "returns a Rational" do
    BigDecimal("3.14159").to_r.should be_kind_of(Rational)
  end

  it "returns a Rational with bignum values" do
    r = BigDecimal("3.141592653589793238462643").to_r
    r.numerator.should eql(3141592653589793238462643)
    r.denominator.should eql(1000000000000000000000000)
  end

  it "returns a Rational from a BigDecimal with an exponent" do
    r = BigDecimal("1E2").to_r
    r.numerator.should eql(100)
    r.denominator.should eql(1)
  end

  it "returns a Rational from a negative BigDecimal with an exponent" do
    r = BigDecimal("-1E2").to_r
    r.numerator.should eql(-100)
    r.denominator.should eql(1)
  end

end
