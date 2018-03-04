require_relative '../../spec_helper'
require_relative 'shared/power'

describe "BigDecimal#power" do
  it_behaves_like :bigdecimal_power, :power
end
