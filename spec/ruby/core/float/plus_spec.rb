require_relative '../../spec_helper'
require_relative 'shared/arithmetic_exception_in_coerce'

describe "Float#+" do
  it_behaves_like :float_arithmetic_exception_in_coerce, :+

  it "returns self plus other" do
    (491.213 + 2).should be_close(493.213, TOLERANCE)
    (9.99 + bignum_value).should be_close(18446744073709551616.0, TOLERANCE)
    (1001.99 + 5.219).should be_close(1007.209, TOLERANCE)
  end
end
