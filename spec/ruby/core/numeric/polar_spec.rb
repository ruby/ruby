require_relative '../../spec_helper'
require_relative '../../shared/complex/numeric/polar'

describe "Numeric#polar" do
  it_behaves_like :numeric_polar, :polar
end
