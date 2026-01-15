require_relative "../../spec_helper"
require_relative 'shared/abs'

describe "Numeric#magnitude" do
  it_behaves_like :numeric_abs, :magnitude
end
