require File.expand_path('../../../spec_helper', __FILE__)
require 'matrix'

describe "Matrix.antisymmetric?" do
  it "returns true for a 0x0 empty matrix" do
    Matrix.empty.antisymmetric?.should be_true
  end

  it "returns false for a non-antisymmetric matrix" do
    Matrix[[1, 2, 3], [4, 5, 6], [7, 8, 9]].antisymmetric?.should be_false
  end

  it "returns true for an antisymmetric matrix" do
    Matrix[[0, -2, 3], [2, 0, 6], [-3, -6, 0]].antisymmetric?.should be_true
  end

  it "returns false if diagonal is not 0" do
    Matrix[[1, -2, 3], [2, 1, 6], [-3, -6, 1]].antisymmetric?.should be_false
  end

  it "raises an error for non-square matrices" do
    [
      Matrix[[0], [0]],
      Matrix[[0, 0]],
      Matrix.empty(0, 2),
      Matrix.empty(2, 0),
    ].each do |rectangular_matrix|
      lambda {
        rectangular_matrix.antisymmetric?
      }.should raise_error(Matrix::ErrDimensionMismatch)
    end
  end
end
