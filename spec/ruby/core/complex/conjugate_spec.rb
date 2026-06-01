require_relative '../../spec_helper'

describe "Complex#conjugate" do
  it "returns the complex conjugate: conj a + bi = a - bi" do
    Complex(3, 5).conjugate.should == Complex(3, -5)
    Complex(3, -5).conjugate.should == Complex(3, 5)
    Complex(-3.0, 5.2).conjugate.should be_close(Complex(-3.0, -5.2), TOLERANCE)
    Complex(3.0, -5.2).conjugate.should be_close(Complex(3.0, 5.2), TOLERANCE)
  end
end
