require_relative '../../spec_helper'

describe "Complex#imaginary" do
  it "returns the imaginary part of self" do
    Complex(1, 0).imaginary.should == 0
    Complex(2, 1).imaginary.should == 1
    Complex(6.7, 8.9).imaginary.should == 8.9
    Complex(1, bignum_value).imaginary.should == bignum_value
  end
end
