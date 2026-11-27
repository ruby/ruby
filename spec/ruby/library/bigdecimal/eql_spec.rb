require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal#eql?" do
  it "is an alias of BigDecimal#==" do
    BigDecimal.instance_method(:eql?).should == BigDecimal.instance_method(:==)
  end
end
