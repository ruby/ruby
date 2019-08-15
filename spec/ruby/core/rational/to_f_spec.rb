require_relative '../../shared/rational/to_f'

describe "Rational#to_f" do
  it_behaves_like :rational_to_f, :to_f
end
