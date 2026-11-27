require_relative '../../spec_helper'

describe "Integer#to_r" do
  it "returns a Rational object" do
    309.to_r.should.instance_of?(Rational)
  end

  it "constructs a rational number with self as the numerator" do
    34.to_r.numerator.should == 34
  end

  it "constructs a rational number with 1 as the denominator" do
    298.to_r.denominator.should == 1
  end

  it "works even if self is a Bignum" do
    bignum = 99999**999
    bignum.should.instance_of?(Integer)
    bignum.to_r.should == Rational(bignum, 1)
  end

  it "raises an ArgumentError if given any arguments" do
    -> { 287.to_r(2) }.should.raise(ArgumentError)
    -> { 9102826.to_r(309, [], 71) }.should.raise(ArgumentError)
  end
end
