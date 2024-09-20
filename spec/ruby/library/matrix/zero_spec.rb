require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require 'matrix'

describe "Matrix.zero" do
  it "returns an object of type Matrix" do
    Matrix.zero(3).should be_kind_of(Matrix)
  end

  it "creates a n x n matrix" do
    m3 = Matrix.zero(3)
    m3.row_size.should == 3
    m3.column_size.should == 3

    m8 = Matrix.zero(8)
    m8.row_size.should == 8
    m8.column_size.should == 8
  end

  it "initializes all cells to 0" do
    size = 10
    m = Matrix.zero(size)

    (0...size).each do |i|
      (0...size).each do |j|
        m[i, j].should == 0
      end
    end
  end

  describe "for a subclass of Matrix" do
    it "returns an instance of that subclass" do
      MatrixSub.zero(3).should be_an_instance_of(MatrixSub)
    end
  end
end

describe "Matrix.zero?" do
  it "returns true for empty matrices" do
    Matrix.empty.should.zero?
    Matrix.empty(3,0).should.zero?
    Matrix.empty(0,3).should.zero?
  end

  it "returns true for matrices with zero entries" do
    Matrix.zero(2,3).should.zero?
  end

  it "returns false for matrices with non zero entries" do
    Matrix[[1]].should_not.zero?
  end
end
