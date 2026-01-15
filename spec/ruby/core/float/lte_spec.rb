require_relative '../../spec_helper'
require_relative 'shared/comparison_exception_in_coerce'

describe "Float#<=" do
  it_behaves_like :float_comparison_exception_in_coerce, :>=

  it "returns true if self is less than or equal to other" do
    (2.0 <= 3.14159).should == true
    (-2.7183 <= -24).should == false
    (0.0 <= 0.0).should == true
    (9_235.9 <= bignum_value).should == true
  end

  it "raises an ArgumentError when given a non-Numeric" do
    -> { 5.0 <= "4"       }.should raise_error(ArgumentError)
    -> { 5.0 <= mock('x') }.should raise_error(ArgumentError)
  end

  it "returns false if one side is NaN" do
    [1.0, 42, bignum_value].each { |n|
      (nan_value <= n).should == false
      (n <= nan_value).should == false
    }
  end

  it "handles positive infinity" do
    [1.0, 42, bignum_value].each { |n|
      (infinity_value <= n).should == false
      (n <= infinity_value).should == true
    }
  end

  it "handles negative infinity" do
    [1.0, 42, bignum_value].each { |n|
      (-infinity_value <= n).should == true
      (n <= -infinity_value).should == false
    }
  end
end
