require_relative '../../spec_helper'
require 'matrix'

describe "Matrix#imag" do
  it "is an alias of Matrix#imaginary" do
    Matrix.instance_method(:imag).should == Matrix.instance_method(:imaginary)
  end
end
