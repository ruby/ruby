require_relative "../../spec_helper"
require_relative '../../shared/rational/divmod'

describe "Rational#divmod when passed a Rational" do
  it_behaves_like :rational_divmod_rat, :divmod
end

describe "Rational#divmod when passed an Integer" do
  it_behaves_like :rational_divmod_int, :divmod
end

describe "Rational#divmod when passed a Float" do
  it_behaves_like :rational_divmod_float, :divmod
end
