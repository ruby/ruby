require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal.new" do
  it "is undefined" do
    BigDecimal.respond_to?(:new).should == false
    -> { BigDecimal.new("1") }.should.raise(NoMethodError)
  end
end
