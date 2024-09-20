require_relative "../../spec_helper"
require_relative '../../shared/rational/remainder'

describe "Rational#remainder" do
  it_behaves_like :rational_remainder, :remainder
end
