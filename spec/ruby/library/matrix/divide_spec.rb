require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'spec_helper'
  require_relative 'fixtures/classes'
  require 'matrix'

  describe "Matrix#/" do
    before :each do
      @a = Matrix[ [1, 2], [3, 4] ]
      @b = Matrix[ [4, 5], [6, 7] ]
      @c = Matrix[ [1.2, 2.4], [3.6, 4.8] ]
    end

    it "returns the result of dividing self by another Matrix" do
      (@a / @b).should be_close_to_matrix([[2.5, -1.5], [1.5, -0.5]])
    end

    # Guard against the Mathn library
    guard -> { !defined?(Math.rsqrt) } do
      it "returns the result of dividing self by a Fixnum" do
        (@a / 2).should == Matrix[ [0, 1], [1, 2] ]
      end

      it "returns the result of dividing self by a Bignum" do
        (@a / bignum_value).should == Matrix[ [0, 0], [0, 0] ]
      end
    end

    it "returns the result of dividing self by a Float" do
      (@c / 1.2).should == Matrix[ [1, 2], [3, 4] ]
    end

    it "raises a Matrix::ErrDimensionMismatch if the matrices are different sizes" do
      -> { @a / Matrix[ [1] ] }.should raise_error(Matrix::ErrDimensionMismatch)
    end

    it "returns an instance of Matrix" do
      (@a / @b).should be_kind_of(Matrix)
    end

    describe "for a subclass of Matrix" do
      it "returns an instance of that subclass" do
        m = MatrixSub.ins
        (m/m).should be_an_instance_of(MatrixSub)
        (m/1).should be_an_instance_of(MatrixSub)
      end
    end

    it "raises a TypeError if other is of wrong type" do
      -> { @a / nil        }.should raise_error(TypeError)
      -> { @a / "a"        }.should raise_error(TypeError)
      -> { @a / [ [1, 2] ] }.should raise_error(TypeError)
      -> { @a / Object.new }.should raise_error(TypeError)
    end
  end
end
