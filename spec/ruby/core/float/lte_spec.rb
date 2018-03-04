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
    lambda { 5.0 <= "4"       }.should raise_error(ArgumentError)
    lambda { 5.0 <= mock('x') }.should raise_error(ArgumentError)
  end
end
