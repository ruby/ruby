require_relative "../../spec_helper"
require_relative '../../shared/rational/inspect'

describe "Rational#inspect" do
  it_behaves_like :rational_inspect, :inspect
end
