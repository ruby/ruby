require_relative '../../spec_helper'
require_relative 'shared/arithmetic_exception_in_coerce'

describe "Float#*" do
  it_behaves_like :float_arithmetic_exception_in_coerce, :*

  it "returns self multiplied by other" do
    (4923.98221 * 2).should be_close(9847.96442, TOLERANCE)
    (6712.5 * 0.25).should be_close(1678.125, TOLERANCE)
    (256.4096 * bignum_value).should be_close(2364961134621118431232.000, TOLERANCE)
  end

  it "raises a TypeError when given a non-Numeric" do
    -> { 13.0 * "10"    }.should raise_error(TypeError)
    -> { 13.0 * :symbol }.should raise_error(TypeError)
  end
end
