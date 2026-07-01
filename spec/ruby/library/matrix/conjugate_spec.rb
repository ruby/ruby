require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Matrix#conjugate" do
  it "returns a matrix with all entries 'conjugated'" do
    Matrix[ [1,   2], [3, 4] ].conjugate.should == Matrix[ [1,   2], [3, 4] ]
    Matrix[ [1.9, Complex(1,1)], [3, 4] ].conjugate.should == Matrix[ [1.9, Complex(1,-1)], [3, 4] ]
  end

  it "returns empty matrices on the same size if empty" do
    Matrix.empty(0, 3).conjugate.should == Matrix.empty(0, 3)
    Matrix.empty(3, 0).conjugate.should == Matrix.empty(3, 0)
  end

  describe "for a subclass of Matrix" do
    it "returns an instance of that subclass" do
      MatrixSub.ins.conjugate.should.instance_of?(MatrixSub)
    end
  end
end
