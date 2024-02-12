require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal#log" do
  it "handles high-precision Rational arguments" do
    result = BigDecimal('0.22314354220170971436137296411949880462556361100856391620766259404746040597133837784E0')
    r = Rational(1_234_567_890, 987_654_321)
    BigMath.log(r, 50).should == result
  end
end
