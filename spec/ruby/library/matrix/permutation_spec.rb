require_relative '../../spec_helper'
require 'matrix'

describe "Matrix#permutation?" do
  it "returns true for a permutation Matrix" do
    Matrix[[0, 1, 0], [0, 0, 1], [1, 0, 0]].permutation?.should == true
  end

  it "returns false for a non permutation square Matrix" do
    Matrix[[0, 1], [0, 0]].permutation?.should == false
    Matrix[[-1, 0], [0, -1]].permutation?.should == false
    Matrix[[1, 0], [1, 0]].permutation?.should == false
    Matrix[[1, 0], [1, 1]].permutation?.should == false
  end

  it "returns true for an empty 0x0 matrix" do
    Matrix.empty(0,0).permutation?.should == true
  end

  it "raises an error for rectangular matrices" do
    [
      Matrix[[0], [0]],
      Matrix[[0, 0]],
      Matrix.empty(0, 2),
      Matrix.empty(2, 0),
    ].each do |rectangular_matrix|
      -> {
        rectangular_matrix.permutation?
      }.should.raise(Matrix::ErrDimensionMismatch)
    end
  end
end
