require_relative '../../spec_helper'
require_relative 'shared/power'

describe "BigDecimal#power" do
  it_behaves_like :bigdecimal_power, :power

  it "uses the same precision for equal values with trailing zeros" do
    BigDecimal("0.12345678").power(-1).should ==
      BigDecimal("0.12345678000000000000").power(-1)
  end
end
