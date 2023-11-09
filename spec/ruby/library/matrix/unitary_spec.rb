require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require 'matrix'

  describe "Matrix.unitary?" do
    it "returns false for non unitary matrices" do
      Matrix[[0, 1], [1, 2]].should_not.unitary?
      Matrix[[0, Complex(0, 2)], [Complex(0, 2), 0]].should_not.unitary?
      Matrix[[1, 1, 0], [0, 1, 1], [1, 0, 1]].should_not.unitary?
    end

    it "returns true for unitary matrices" do
      Matrix[[0, Complex(0, 1)], [Complex(0, 1), 0]].should.unitary?
    end

    it "returns true for unitary matrices with a Complex and a negative #imag" do
      Matrix[[0, Complex(0, 1)], [Complex(0, -1), 0]].should.unitary?
    end

    it "raises an error for rectangular matrices" do
      [
        Matrix[[0], [0]],
        Matrix[[0, 0]],
        Matrix.empty(0, 2),
        Matrix.empty(2, 0),
      ].each do |rectangular_matrix|
        -> {
          rectangular_matrix.unitary?
        }.should raise_error(Matrix::ErrDimensionMismatch)
      end
    end
  end
end
