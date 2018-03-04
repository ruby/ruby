require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal.ver" do

  it "returns the Version number" do
    lambda {BigDecimal.ver }.should_not raise_error()
    BigDecimal.ver.should_not == nil
  end

end
