require_relative '../../shared/rational/floor'

describe "Rational#floor" do
  it_behaves_like :rational_floor, :floor
end
