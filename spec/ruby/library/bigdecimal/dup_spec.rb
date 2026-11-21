require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal#dup" do
  before :each do
    @obj = BigDecimal("1.2345")
  end

  it "returns self" do
    copy = @obj.dup

    copy.should.equal?(@obj)
  end
end
