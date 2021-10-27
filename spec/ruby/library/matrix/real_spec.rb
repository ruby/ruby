require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'fixtures/classes'
  require 'matrix'

  describe "Matrix#real?" do
    it "returns true for matrices with all real entries" do
      Matrix[ [1,   2], [3, 4] ].real?.should be_true
      Matrix[ [1.9, 2], [3, 4] ].real?.should be_true
    end

    it "returns true for empty matrices" do
      Matrix.empty.real?.should be_true
    end

    it "returns false if one element is a Complex" do
      Matrix[ [Complex(1,1), 2], [3, 4] ].real?.should be_false
    end

    # Guard against the Mathn library
    guard -> { !defined?(Math.rsqrt) } do
      it "returns false if one element is a Complex whose imaginary part is 0" do
        Matrix[ [Complex(1,0), 2], [3, 4] ].real?.should be_false
      end
    end
  end

  describe "Matrix#real" do
    it "returns a matrix with the real part of the elements of the receiver" do
      Matrix[ [1,   2], [3, 4] ].real.should == Matrix[ [1,   2], [3, 4] ]
      Matrix[ [1.9, Complex(1,1)], [Complex(-0.42, 0), 4] ].real.should == Matrix[ [1.9, 1], [-0.42, 4] ]
    end

    it "returns empty matrices on the same size if empty" do
      Matrix.empty(0, 3).real.should == Matrix.empty(0, 3)
      Matrix.empty(3, 0).real.should == Matrix.empty(3, 0)
    end

    describe "for a subclass of Matrix" do
      it "returns an instance of that subclass" do
        MatrixSub.ins.real.should be_an_instance_of(MatrixSub)
      end
    end
  end
end
