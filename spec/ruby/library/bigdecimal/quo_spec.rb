require_relative '../../spec_helper'
require_relative 'shared/quo'
require 'bigdecimal'

describe "BigDecimal#quo" do
  it_behaves_like :bigdecimal_quo, :quo, []

  it "returns NaN if NaN is involved" do
    BigDecimal("1").quo(BigDecimal("NaN")).should.nan?
    BigDecimal("NaN").quo(BigDecimal("1")).should.nan?
  end
end
