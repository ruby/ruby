require_relative "../../spec_helper"
require_relative 'shared/abs'

describe "Rational#abs" do
  it_behaves_like :rational_abs, :magnitude
end
