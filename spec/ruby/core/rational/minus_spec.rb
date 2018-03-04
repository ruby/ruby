require_relative '../../shared/rational/minus'
require_relative '../../shared/rational/arithmetic_exception_in_coerce'

describe "Rational#-" do
  it_behaves_like :rational_minus, :-
  it_behaves_like :rational_arithmetic_exception_in_coerce, :-
end
