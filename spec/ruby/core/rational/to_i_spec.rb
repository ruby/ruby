require_relative '../../shared/rational/to_i'

describe "Rational#to_i" do
  it_behaves_like :rational_to_i, :to_i
end
