require_relative '../../spec_helper'

describe "Complex#abs2" do
  it "returns the sum of the squares of the real and imaginary parts" do
    Complex(1, -2).abs2.should == 1 + 4
    Complex(-0.1, 0.2).abs2.should be_close(0.01 + 0.04, TOLERANCE)
    Complex(0).abs2.should == 0
  end
end
