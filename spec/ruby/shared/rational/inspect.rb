require_relative '../../spec_helper'

describe :rational_inspect, shared: true do
  it "returns a string representation of self" do
    Rational(3, 4).inspect.should == "(3/4)"
    Rational(-5, 8).inspect.should == "(-5/8)"
    Rational(-1, -2).inspect.should == "(1/2)"

    # Guard against the Mathn library
    guard -> { !defined?(Math.rsqrt) } do
      Rational(bignum_value, 1).inspect.should == "(#{bignum_value}/1)"
    end
  end
end
