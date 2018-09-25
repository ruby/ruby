require_relative '../../spec_helper'

describe "Complex.polar" do
  it "returns a complex number in terms of radius and angle" do
    Complex.polar(50, 60).should be_close(Complex(-47.6206490207578, -15.2405310551108), TOLERANCE)
    Complex.polar(-10, -20).should be_close(Complex(-4.08082061813392, 9.12945250727628), TOLERANCE)
  end

  it "raises a TypeError when given non real arguments" do
    lambda{ Complex.polar(nil)      }.should raise_error(TypeError)
    lambda{ Complex.polar(nil, nil) }.should raise_error(TypeError)
  end
end

describe "Complex#polar" do
  it "returns the absolute value and the argument" do
    a = Complex(3, 4)
    a.polar.size.should == 2
    a.polar.first.should == 5.0
    a.polar.last.should be_close(0.927295218001612, TOLERANCE)

    b = Complex(-3.5, 4.7)
    b.polar.size.should == 2
    b.polar.first.should be_close(5.86003412959345, TOLERANCE)
    b.polar.last.should be_close(2.21088447955664, TOLERANCE)
  end
end
