require_relative '../../spec_helper'

ruby_version_is ""..."3.4" do
  require_relative 'shared/modulo'

  describe "BigDecimal#%" do
    it_behaves_like :bigdecimal_modulo, :%
    it_behaves_like :bigdecimal_modulo_zerodivisionerror, :%
  end

  describe "BigDecimal#modulo" do
    it_behaves_like :bigdecimal_modulo, :modulo
    it_behaves_like :bigdecimal_modulo_zerodivisionerror, :modulo
  end
end
