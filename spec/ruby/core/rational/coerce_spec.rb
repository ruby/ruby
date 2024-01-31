require_relative "../../spec_helper"

ruby_version_is ""..."3.4" do
  require_relative '../../shared/rational/coerce'

  describe "Rational#coerce" do
    it_behaves_like :rational_coerce, :coerce
  end
end
