require File.expand_path('../../../shared/rational/divide', __FILE__)
require File.expand_path('../../../shared/rational/arithmetic_exception_in_coerce', __FILE__)

describe "Rational#/" do
  it_behaves_like :rational_divide, :/
  it_behaves_like :rational_arithmetic_exception_in_coerce, :/
end

describe "Rational#/ when passed an Integer" do
  it_behaves_like :rational_divide_int, :/
end

describe "Rational#/ when passed a Rational" do
  it_behaves_like :rational_divide_rat, :/
end

describe "Rational#/ when passed a Float" do
  it_behaves_like :rational_divide_float, :/
end
