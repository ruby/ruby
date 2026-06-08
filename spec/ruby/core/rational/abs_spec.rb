require_relative "../../spec_helper"

describe "Rational#abs" do
  it "returns self's absolute value" do
    Rational(3, 4).abs.should == Rational(3, 4)
    Rational(-3, 4).abs.should == Rational(3, 4)
    Rational(3, -4).abs.should == Rational(3, 4)

    Rational(bignum_value, -bignum_value).abs.should == Rational(bignum_value, bignum_value)
  end
end
