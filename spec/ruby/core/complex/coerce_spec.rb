require_relative '../../shared/complex/coerce'

describe "Complex#coerce" do
  it_behaves_like :complex_coerce, :coerce
end
