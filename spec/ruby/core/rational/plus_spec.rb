require_relative '../../shared/rational/plus'
require_relative '../../shared/rational/arithmetic_exception_in_coerce'

describe "Rational#+" do
  it_behaves_like :rational_plus, :+
  it_behaves_like :rational_arithmetic_exception_in_coerce, :+
end

describe "Rational#+ with a Rational" do
  it_behaves_like :rational_plus_rat, :+
end
describe "Rational#+ with a Float" do
  it_behaves_like :rational_plus_float, :+
end

describe "Rational#+ with an Integer" do
  it_behaves_like :rational_plus_int, :+
end
