require_relative '../../spec_helper'
require_relative 'shared/modulo'
require 'bigdecimal'

describe "BigDecimal#%" do
  it_behaves_like :bigdecimal_modulo, :%

  it "raises ZeroDivisionError if other is zero" do
    bd5667 = BigDecimal("5667.19")

    -> { bd5667 % 0 }.should.raise(ZeroDivisionError)
    -> { bd5667 % BigDecimal("0") }.should.raise(ZeroDivisionError)
    -> { @zero % @zero }.should.raise(ZeroDivisionError)
  end
end

describe "BigDecimal#modulo" do
  it "is an alias of BigDecimal#%" do
    BigDecimal.instance_method(:modulo).should == BigDecimal.instance_method(:%)
  end
end
