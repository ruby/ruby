require_relative '../../spec_helper'
require_relative 'shared/comparison_exception_in_coerce'

describe "Float#>=" do
  it_behaves_like :float_comparison_exception_in_coerce, :>=

  it "returns true if self is greater than or equal to other" do
    (5.2 >= 5.2).should == true
    (9.71 >= 1).should == true
    (5.55382 >= 0xfabdafbafcab).should == false
  end

  it "raises an ArgumentError when given a non-Numeric" do
    -> { 5.0 >= "4"       }.should raise_error(ArgumentError)
    -> { 5.0 >= mock('x') }.should raise_error(ArgumentError)
  end
end
