require_relative '../../shared/rational/equal_value'

describe "Rational#==" do
  it_behaves_like :rational_equal_value, :==
end

describe "Rational#== when passed a Rational" do
  it_behaves_like :rational_equal_value_rat, :==
end

describe "Rational#== when passed a Float" do
  it_behaves_like :rational_equal_value_float, :==
end

describe "Rational#== when passed an Integer" do
  it_behaves_like :rational_equal_value_int, :==
end
