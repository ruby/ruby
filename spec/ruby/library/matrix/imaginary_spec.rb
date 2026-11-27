require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require 'matrix'

describe "Matrix#imaginary" do
  it "returns a matrix with the imaginary part of the elements of the receiver" do
    Matrix[ [1,   2], [3, 4] ].imaginary.should == Matrix[ [0,   0], [0, 0] ]
    Matrix[ [1.9, Complex(1,1)], [Complex(-2,0.42), 4] ].imaginary.should == Matrix[ [0, 1], [0.42, 0] ]
  end

  it "returns empty matrices on the same size if empty" do
    Matrix.empty(0, 3).imaginary.should == Matrix.empty(0, 3)
    Matrix.empty(3, 0).imaginary.should == Matrix.empty(3, 0)
  end

  describe "for a subclass of Matrix" do
    it "returns an instance of that subclass" do
      MatrixSub.ins.imaginary.should.instance_of?(MatrixSub)
    end
  end
end
