require_relative '../../spec_helper'
require 'matrix'

describe "Matrix#singular?" do
  it "returns true for singular matrices" do
    m = Matrix[ [1,2,3], [3,4,3], [0,0,0] ]
    m.singular?.should == true

    m = Matrix[ [1,2,9], [3,4,9], [1,2,9] ]
    m.singular?.should == true
  end

  it "returns false if the Matrix is regular" do
    Matrix[ [0,1], [1,0] ].singular?.should == false
  end

  it "returns false for an empty 0x0 matrix" do
    Matrix.empty(0,0).singular?.should == false
  end

  it "raises an error for rectangular matrices" do
    -> {
      Matrix[[1], [2], [3]].singular?
    }.should.raise(Matrix::ErrDimensionMismatch)

    -> {
      Matrix.empty(3,0).singular?
    }.should.raise(Matrix::ErrDimensionMismatch)
  end

end
