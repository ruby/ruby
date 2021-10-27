require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require 'matrix'

  describe "Matrix#antisymmetric?" do
    it "returns true for an antisymmetric Matrix" do
      Matrix[[0, -2, Complex(1, 3)], [2, 0, 5], [-Complex(1, 3), -5, 0]].antisymmetric?.should be_true
    end

    it "returns true for a 0x0 empty matrix" do
      Matrix.empty.antisymmetric?.should be_true
    end

    it "returns false for non-antisymmetric matrices" do
      [
        Matrix[[1, 2, 3], [4, 5, 6], [7, 8, 9]],
        Matrix[[1, -2, 3], [2, 0, 6], [-3, -6, 0]],  # wrong diagonal element
        Matrix[[0, 2, -3], [2, 0, 6], [-3, 6, 0]]    # only signs wrong
      ].each do |matrix|
        matrix.antisymmetric?.should be_false
      end
    end

    it "raises an error for rectangular matrices" do
      [
        Matrix[[0], [0]],
        Matrix[[0, 0]],
        Matrix.empty(0, 2),
        Matrix.empty(2, 0),
      ].each do |rectangular_matrix|
        -> {
          rectangular_matrix.antisymmetric?
        }.should raise_error(Matrix::ErrDimensionMismatch)
      end
    end
  end
end
