require_relative '../../spec_helper'

describe "Complex#abs" do
  it "returns the modulus: |a + bi| = sqrt((a ^ 2) + (b ^ 2))" do
    Complex(0, 0).abs.should == 0
    Complex(3, 4).abs.should == 5 # well-known integer case
    Complex(-3, 4).abs.should == 5
    Complex(1, -1).abs.should be_close(Math.sqrt(2), TOLERANCE)
    Complex(6.5, 0).abs.should be_close(6.5, TOLERANCE)
    Complex(0, -7.2).abs.should be_close(7.2, TOLERANCE)
  end
end
