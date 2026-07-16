require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal#clone" do
  it "is an alias of BigDecimal#dup" do
    BigDecimal.instance_method(:clone).should == BigDecimal.instance_method(:dup)
  end
end
