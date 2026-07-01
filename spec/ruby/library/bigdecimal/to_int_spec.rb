require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal#to_int" do
  it "is an alias of BigDecimal#to_i" do
    BigDecimal.instance_method(:to_int).should == BigDecimal.instance_method(:to_i)
  end
end
