require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require 'matrix'

  describe "Matrix#regular?" do

    it "returns false for singular matrices" do
      m = Matrix[ [1,2,3], [3,4,3], [0,0,0] ]
      m.regular?.should be_false

      m = Matrix[ [1,2,9], [3,4,9], [1,2,9] ]
      m.regular?.should be_false
    end

    it "returns true if the Matrix is regular" do
      Matrix[ [0,1], [1,0] ].regular?.should be_true
    end

    it "returns true for an empty 0x0 matrix" do
      Matrix.empty(0,0).regular?.should be_true
    end

    it "raises an error for rectangular matrices" do
      -> {
        Matrix[[1], [2], [3]].regular?
      }.should raise_error(Matrix::ErrDimensionMismatch)

      -> {
        Matrix.empty(3,0).regular?
      }.should raise_error(Matrix::ErrDimensionMismatch)
    end
  end
end
