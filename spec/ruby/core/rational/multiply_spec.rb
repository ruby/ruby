require_relative "../../spec_helper"
require_relative '../../shared/rational/multiply'
require_relative '../../shared/rational/arithmetic_exception_in_coerce'

describe "Rational#*" do
  it_behaves_like :rational_multiply, :*
  it_behaves_like :rational_arithmetic_exception_in_coerce, :*
end

describe "Rational#* passed a Rational" do
  it_behaves_like :rational_multiply_rat, :*
end

describe "Rational#* passed a Float" do
  it_behaves_like :rational_multiply_float, :*
end

describe "Rational#* passed an Integer" do
  it_behaves_like :rational_multiply_int, :*
end
