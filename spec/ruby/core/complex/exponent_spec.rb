require_relative '../../shared/complex/exponent'

describe "Complex#**" do
  it_behaves_like :complex_exponent, :**
end
