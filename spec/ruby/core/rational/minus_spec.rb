require File.expand_path('../../../shared/rational/minus', __FILE__)
require File.expand_path('../../../shared/rational/arithmetic_exception_in_coerce', __FILE__)

describe "Rational#-" do
  it_behaves_like(:rational_minus, :-)
  it_behaves_like :rational_arithmetic_exception_in_coerce, :-
end
