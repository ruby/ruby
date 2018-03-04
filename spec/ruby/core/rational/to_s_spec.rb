require_relative '../../shared/rational/to_s'

describe "Rational#to_s" do
  it_behaves_like :rational_to_s, :to_s
end
