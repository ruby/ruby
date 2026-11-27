require_relative '../fixtures/classes'
require 'matrix'

describe :equal, shared: true do
  before do
    @matrix = Matrix[ [1, 2, 3, 4, 5], [2, 3, 4, 5, 6] ]
  end

  it "returns true for self" do
    @matrix.send(@method, @matrix).should == true
  end

  it "returns true for equal matrices" do
    @matrix.send(@method, Matrix[ [1, 2, 3, 4, 5], [2, 3, 4, 5, 6] ]).should == true
  end

  it "returns false for different matrices" do
    @matrix.send(@method, Matrix[ [42, 2, 3, 4, 5], [2, 3, 4, 5, 6] ]).should == false
    @matrix.send(@method, Matrix[ [1, 2, 3, 4, 5, 6], [2, 3, 4, 5, 6, 7] ]).should == false
    @matrix.send(@method, Matrix[ [1, 2, 3], [2, 3, 4] ]).should == false
  end

  it "returns false for different empty matrices" do
    Matrix.empty(42, 0).send(@method, Matrix.empty(6, 0)).should == false
    Matrix.empty(0, 42).send(@method, Matrix.empty(0, 6)).should == false
    Matrix.empty(0, 0).send(@method, Matrix.empty(6, 0)).should == false
    Matrix.empty(0, 0).send(@method, Matrix.empty(0, 6)).should == false
  end

  it "doesn't distinguish on subclasses" do
    MatrixSub.ins.send(@method, Matrix.I(2)).should == true
  end
end
