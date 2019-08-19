require_relative '../../shared/rational/exponent'

describe "Rational#**" do
  it_behaves_like :rational_exponent, :**
end
