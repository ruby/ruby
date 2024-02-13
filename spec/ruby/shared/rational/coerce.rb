require_relative '../../spec_helper'

require 'bigdecimal'

describe :rational_coerce, shared: true do
  it "returns the passed argument, self as Float, when given a Float" do
    result = Rational(3, 4).coerce(1.0)
    result.should == [1.0, 0.75]
    result.first.is_a?(Float).should be_true
    result.last.is_a?(Float).should be_true
  end

  it "returns the passed argument, self as Rational, when given an Integer" do
    result = Rational(3, 4).coerce(10)
    result.should == [Rational(10, 1), Rational(3, 4)]
    result.first.is_a?(Rational).should be_true
    result.last.is_a?(Rational).should be_true
  end

  it "coerces to Rational, when given a Complex" do
    Rational(3, 4).coerce(Complex(5)).should == [Rational(5, 1), Rational(3, 4)]
    Rational(12, 4).coerce(Complex(5, 1)).should == [Complex(5, 1), Complex(3)]
  end

  it "returns [argument, self] when given a Rational" do
    Rational(3, 7).coerce(Rational(9, 2)).should == [Rational(9, 2), Rational(3, 7)]
  end

  it "raises an error when passed a BigDecimal" do
    -> {
      Rational(500, 3).coerce(BigDecimal('166.666666666'))
    }.should raise_error(TypeError, /BigDecimal can't be coerced into Rational/)
  end
end
