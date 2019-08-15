require_relative '../../shared/rational/numerator'

describe "Rational#numerator" do
  it_behaves_like :rational_numerator, :numerator
end
