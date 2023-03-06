require_relative "../../spec_helper"
require_relative '../../shared/rational/fdiv'

describe "Rational#fdiv" do
  it_behaves_like :rational_fdiv, :fdiv
end
