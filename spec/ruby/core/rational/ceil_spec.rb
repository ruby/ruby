require_relative "../../spec_helper"
require_relative '../../shared/rational/ceil'

describe "Rational#ceil" do
  it_behaves_like :rational_ceil, :ceil
end
