require_relative "../../spec_helper"
require_relative '../../shared/rational/coerce'

describe "Rational#coerce" do
  it_behaves_like :rational_coerce, :coerce
end
