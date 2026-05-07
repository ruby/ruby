require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require 'matrix'

describe "Matrix#-" do
  before :each do
    @a = Matrix[ [1, 2], [3, 4] ]
    @b = Matrix[ [4, 5], [6, 7] ]
  end

  it "returns the result of subtracting the corresponding elements of other from self" do
    (@a - @b).should == Matrix[ [-3,-3], [-3,-3] ]
  end

  it "returns an instance of Matrix" do
    (@a - @b).should.is_a?(Matrix)
  end

  it "raises a Matrix::ErrDimensionMismatch if the matrices are different sizes" do
    -> { @a - Matrix[ [1] ] }.should.raise(Matrix::ErrDimensionMismatch)
  end

  it "raises a ExceptionForMatrix::ErrOperationNotDefined if other is a Numeric Type" do
    -> { @a - 2            }.should.raise(Matrix::ErrOperationNotDefined)
    -> { @a - 1.2          }.should.raise(Matrix::ErrOperationNotDefined)
    -> { @a - bignum_value }.should.raise(Matrix::ErrOperationNotDefined)
  end

  it "raises a TypeError if other is of wrong type" do
    -> { @a - nil        }.should.raise(TypeError)
    -> { @a - "a"        }.should.raise(TypeError)
    -> { @a - [ [1, 2] ] }.should.raise(TypeError)
    -> { @a - Object.new }.should.raise(TypeError)
  end

  describe "for a subclass of Matrix" do
    it "returns an instance of that subclass" do
      m = MatrixSub.ins
      (m-m).should.instance_of?(MatrixSub)
    end
  end
end
