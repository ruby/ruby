require_relative "../../spec_helper"
require_relative '../../shared/rational/comparison'

describe "Rational#<=> when passed a Rational object" do
  it_behaves_like :rational_cmp_rat, :<=>
end

describe "Rational#<=> when passed an Integer object" do
  it_behaves_like :rational_cmp_int, :<=>
end

describe "Rational#<=> when passed a Float object" do
  it_behaves_like :rational_cmp_float, :<=>
end

describe "Rational#<=> when passed an Object that responds to #coerce" do
  it_behaves_like :rational_cmp_coerce, :<=>
  it_behaves_like :rational_cmp_coerce_exception, :<=>
end

describe "Rational#<=> when passed a non-Numeric Object that doesn't respond to #coerce" do
  it_behaves_like :rational_cmp_other, :<=>
end
