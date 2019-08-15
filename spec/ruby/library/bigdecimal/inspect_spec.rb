require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal#inspect" do

  before :each do
    @bigdec = BigDecimal("1234.5678")
  end

  it "returns String" do
    @bigdec.inspect.kind_of?(String).should == true
  end

  it "looks like this" do
    @bigdec.inspect.should == "0.12345678e4"
  end

  it "does not add an exponent for zero values" do
    BigDecimal("0").inspect.should == "0.0"
    BigDecimal("+0").inspect.should == "0.0"
    BigDecimal("-0").inspect.should == "-0.0"
  end

  it "properly cases non-finite values" do
    BigDecimal("NaN").inspect.should == "NaN"
    BigDecimal("Infinity").inspect.should == "Infinity"
    BigDecimal("+Infinity").inspect.should == "Infinity"
    BigDecimal("-Infinity").inspect.should == "-Infinity"
  end
end
