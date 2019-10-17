require_relative '../../spec_helper'

describe :rational_to_s, shared: true do
  it "returns a string representation of self" do
    # Guard against the Mathn library
    guard -> { !defined?(Math.rsqrt) } do
      Rational(1, 1).to_s.should == "1/1"
      Rational(2, 1).to_s.should == "2/1"
    end
    Rational(1, 2).to_s.should == "1/2"
    Rational(-1, 3).to_s.should == "-1/3"
    Rational(1, -3).to_s.should == "-1/3"
  end
end
