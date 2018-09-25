require_relative '../../spec_helper'

describe "Complex::I" do
  it "is Complex(0, 1)" do
    Complex::I.should eql(Complex(0, 1))
  end
end
