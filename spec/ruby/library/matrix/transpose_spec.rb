require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Matrix#transpose" do
  it "returns a transposed matrix" do
    Matrix[[1, 2], [3, 4], [5, 6]].transpose.should == Matrix[[1, 3, 5], [2, 4, 6]]
  end

  it "can transpose empty matrices" do
    m = Matrix[[], [], []]
    m.transpose.transpose.should == m
  end

  describe "for a subclass of Matrix" do
    it "returns an instance of that subclass" do
      MatrixSub.ins.transpose.should.instance_of?(MatrixSub)
    end
  end
end
