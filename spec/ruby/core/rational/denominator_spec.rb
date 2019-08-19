require_relative '../../shared/rational/denominator'

describe "Rational#denominator" do
  it_behaves_like :rational_denominator, :denominator
end
