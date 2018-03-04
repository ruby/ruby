require_relative '../../spec_helper'
require_relative '../../shared/complex/numeric/arg'

describe "Numeric#angle" do
  it_behaves_like :numeric_arg, :angle
end
