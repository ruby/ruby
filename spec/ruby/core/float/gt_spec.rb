require_relative '../../spec_helper'
require_relative 'shared/comparison_exception_in_coerce'

describe "Float#>" do
  it_behaves_like :float_comparison_exception_in_coerce, :>

  it "returns true if self is greater than other" do
    (1.5 > 1).should == true
    (2.5 > 3).should == false
    (45.91 > bignum_value).should == false
  end

  it "raises an ArgumentError when given a non-Numeric" do
    -> { 5.0 > "4"       }.should raise_error(ArgumentError)
    -> { 5.0 > mock('x') }.should raise_error(ArgumentError)
  end
end
