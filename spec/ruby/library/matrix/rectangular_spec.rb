require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require 'matrix'

describe "Matrix#rectangular" do
  it "returns [receiver.real, receiver.imag]" do
    m = Matrix[ [1.2, Complex(1,2)], [Complex(-2,0.42), 4] ]
    m.rectangular.should == [m.real, m.imag]

    m = Matrix.empty(3, 0)
    m.rectangular.should == [m.real, m.imag]
  end

  describe "for a subclass of Matrix" do
    it "returns instances of that subclass" do
      MatrixSub.ins.rectangular.each{|m| m.should.instance_of?(MatrixSub) }
    end
  end
end
