require_relative "../../spec_helper"
require_relative '../../shared/rational/divide'

describe "Rational#quo" do
  it_behaves_like :rational_divide, :quo
end
