require_relative '../../spec_helper'

ruby_version_is ""..."3.4" do
  require 'bigdecimal'

  describe "BigDecimal.double_fig" do
    # The result depends on the CPU and OS
    it "returns the number of digits a Float number is allowed to have" do
      BigDecimal.double_fig.should_not == nil
    end
  end
end
