require_relative '../../spec_helper'

describe "Complex#arg" do
  it "returns the argument -- i.e., the angle from (1, 0) in the complex plane" do
    two_pi = 2 * Math::PI
    (Complex(1, 0).arg % two_pi).should be_close(0, TOLERANCE)
    (Complex(0, 2).arg % two_pi).should be_close(Math::PI * 0.5, TOLERANCE)
    (Complex(-100, 0).arg % two_pi).should be_close(Math::PI, TOLERANCE)
    (Complex(0, -75.3).arg % two_pi).should be_close(Math::PI * 1.5, TOLERANCE)
  end
end
