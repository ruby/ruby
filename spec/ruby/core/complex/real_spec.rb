require_relative '../../spec_helper'

describe "Complex#real" do
  it "returns the real part of self" do
    Complex(1, 0).real.should == 1
    Complex(2, 1).real.should == 2
    Complex(6.7, 8.9).real.should == 6.7
    Complex(bignum_value, 3).real.should == bignum_value
  end
end

describe "Complex#real?" do
  it "returns false if there is an imaginary part" do
    Complex(2,3).real?.should be_false
  end

  it "returns false if there is not an imaginary part" do
    Complex(2).real?.should be_false
  end

  it "returns false if the real part is Infinity" do
    Complex(infinity_value).real?.should be_false
  end

  it "returns false if the real part is NaN" do
    Complex(nan_value).real?.should be_false
  end
end
