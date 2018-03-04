require_relative '../../../spec_helper'
require 'matrix'

describe "Matrix::LUPDecomposition#initialize" do
  it "raises an error if argument is not a matrix" do
    lambda {
      Matrix::LUPDecomposition.new([[]])
    }.should raise_error(TypeError)
    lambda {
      Matrix::LUPDecomposition.new(42)
    }.should raise_error(TypeError)
  end
end
