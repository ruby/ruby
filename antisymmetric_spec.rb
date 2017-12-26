require File.expand_path('../../../spec_helper', __FILE__)
require 'matrix'

describe "Matrix.antisymmetric?" do
  it "returns true for an antisymmetric matrix" do
    Matrix[[1, 2, 3], [4, 5, 6], [7, 8, 9]].antisymmetric?.should be_true
  end

  it "returns true for a 0x0 empty matrix" do
    Matrix.empty.symmetric?should be_true
  end

  it "returns false for an asymmetric Matrix" do
    Matrix[[1, 2],[-2, 1]].symmetric?.should be_false
  end

  it "raises an error for rectangular matrices" do
    [
      Matrix[[0], [0]],
      Matrix[[0, 0]],
      Matrix.empty(0, 2),
      Matrix.empty(2, 0),
    ].each do |rectangular_matrix|
      lambda {
        rectangular_matrix.symmetric?
      }.should raise_error(Matrix::ErrDimensionMismatch)
    end
  end
end
