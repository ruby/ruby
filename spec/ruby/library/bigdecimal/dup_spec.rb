require_relative '../../spec_helper'

ruby_version_is ""..."3.4" do
  require_relative 'shared/clone'

  describe "BigDecimal#dup" do
    it_behaves_like :bigdecimal_clone, :dup
  end
end
