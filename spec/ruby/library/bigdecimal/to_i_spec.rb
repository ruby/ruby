require_relative '../../spec_helper'

ruby_version_is ""..."3.4" do
  require_relative 'shared/to_int'
  require 'bigdecimal'

  describe "BigDecimal#to_i" do
      it_behaves_like :bigdecimal_to_int, :to_i
  end
end
