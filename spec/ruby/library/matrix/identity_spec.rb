require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require 'matrix'

describe "Matrix.identity" do
  it "returns a Matrix" do
    Matrix.identity(2).should.is_a?(Matrix)
  end

  it "returns a n x n identity matrix" do
    Matrix.identity(3).should == Matrix.scalar(3, 1)
    Matrix.identity(100).should == Matrix.scalar(100, 1)
  end

  describe "for a subclass of Matrix" do
    it "returns an instance of that subclass" do
      MatrixSub.identity(2).should.instance_of?(MatrixSub)
    end
  end
end
