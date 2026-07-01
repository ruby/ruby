require_relative '../../spec_helper'

describe "Complex#imag" do
  it "is an alias of Complex#imaginary" do
    Complex.instance_method(:imag).should == Complex.instance_method(:imaginary)
  end
end
