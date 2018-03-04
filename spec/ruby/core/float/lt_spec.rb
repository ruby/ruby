require_relative '../../spec_helper'
require_relative 'shared/comparison_exception_in_coerce'

describe "Float#<" do
  it_behaves_like :float_comparison_exception_in_coerce, :<

  it "returns true if self is less than other" do
    (71.3 < 91.8).should == true
    (192.6 < -500).should == false
    (-0.12 < 0x4fffffff).should == true
  end

  it "raises an ArgumentError when given a non-Numeric" do
    lambda { 5.0 < "4"       }.should raise_error(ArgumentError)
    lambda { 5.0 < mock('x') }.should raise_error(ArgumentError)
  end
end
