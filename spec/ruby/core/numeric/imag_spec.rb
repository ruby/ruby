require_relative '../../spec_helper'

describe "Numeric#imag" do
  it "is an alias of Numeric#imaginary" do
    Numeric.instance_method(:imag).should == Numeric.instance_method(:imaginary)
  end
end
