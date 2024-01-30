require_relative '../../spec_helper'

ruby_version_is ""..."3.4" do
  require_relative 'shared/eql'

  describe "BigDecimal#eql?" do
    it_behaves_like :bigdecimal_eql, :eql?
  end
end
