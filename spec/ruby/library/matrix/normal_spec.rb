require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require 'matrix'

  describe "Matrix.normal?" do
    # it "returns false for non normal matrices" do
    #   Matrix[[0, 1], [1, 2]].should_not.normal?
    # end

    it "returns true for normal matrices" do
      Matrix[[1, 1, 0], [0, 1, 1], [1, 0, 1]].should.normal?
      Matrix[[0, Complex(0, 2)], [Complex(0, -2), 0]].should.normal?
    end

    it "raises an error for rectangular matrices" do
      [
        Matrix[[0], [0]],
        Matrix[[0, 0]],
        Matrix.empty(0, 2),
        Matrix.empty(2, 0),
      ].each do |rectangular_matrix|
        -> {
          rectangular_matrix.normal?
        }.should raise_error(Matrix::ErrDimensionMismatch)
      end
    end
  end
end
