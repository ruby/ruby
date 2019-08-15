require_relative '../../spec_helper'
require_relative 'shared/arg'

describe "Numeric#angle" do
  it_behaves_like :numeric_arg, :angle
end
