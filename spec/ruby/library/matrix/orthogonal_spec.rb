require_relative '../../spec_helper'
require 'matrix'

describe "Matrix.orthogonal?" do
  it "returns false for non orthogonal matrices" do
    Matrix[[0, 1], [1, 2]].should_not.orthogonal?
    Matrix[[1, 1, 0], [0, 1, 1], [1, 0, 1]].should_not.orthogonal?
  end

  it "returns true for orthogonal matrices" do
    Matrix[[0, 1], [1, 0]].should.orthogonal?
  end

  it "raises an error for rectangular matrices" do
    [
      Matrix[[0], [0]],
      Matrix[[0, 0]],
      Matrix.empty(0, 2),
      Matrix.empty(2, 0),
    ].each do |rectangular_matrix|
      -> {
        rectangular_matrix.orthogonal?
      }.should raise_error(Matrix::ErrDimensionMismatch)
    end
  end
end
