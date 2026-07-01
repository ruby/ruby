require_relative '../../spec_helper'
require 'bigdecimal'


describe "BigDecimal#===" do
  it "is an alias of BigDecimal#==" do
    BigDecimal.instance_method(:===).should == BigDecimal.instance_method(:==)
  end
end
