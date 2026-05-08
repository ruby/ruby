require_relative '../../../spec_helper'
require 'prime'

describe "Integer#prime?" do
  it "returns a true value for prime numbers" do
    2.prime?.should == true
    3.prime?.should == true
    (2**31-1).prime?.should == true  # 8th Mersenne prime (M8)
  end

  it "returns a false value for composite numbers" do
    4.prime?.should == false
    15.prime?.should == false
    (2**32-1).prime?.should == false
    ( (2**17-1)*(2**19-1) ).prime?.should == false  # M6*M7
  end
end
