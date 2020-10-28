require_relative '../../../spec_helper'
require 'matrix'

describe "Matrix::EigenvalueDecomposition#initialize" do
  it "raises an error if argument is not a matrix" do
    -> {
      Matrix::EigenvalueDecomposition.new([[]])
    }.should raise_error(TypeError)
    -> {
      Matrix::EigenvalueDecomposition.new(42)
    }.should raise_error(TypeError)
  end

  it "raises an error if matrix is not square" do
    -> {
      Matrix::EigenvalueDecomposition.new(Matrix[[1, 2]])
    }.should raise_error(Matrix::ErrDimensionMismatch)
  end

  it "never hangs" do
    m = Matrix[ [0,0,0,0,0], [0,0,0,0,1], [0,0,0,1,0], [1,1,0,0,1], [1,0,1,0,1] ]
    Matrix::EigenvalueDecomposition.new(m).should_not == "infinite loop"
  end
end
