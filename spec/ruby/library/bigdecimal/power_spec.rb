require_relative '../../spec_helper'

ruby_version_is ""..."3.4" do
  require_relative 'shared/power'

  describe "BigDecimal#power" do
    it_behaves_like :bigdecimal_power, :power
  end
end
