require_relative '../../spec_helper'
require_relative '../../shared/rational/round'

describe "Rational#round" do
  it_behaves_like :rational_round, :round
end
