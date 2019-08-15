require_relative '../../spec_helper'
require_relative 'shared/arg'

describe "Numeric#phase" do
  it_behaves_like :numeric_arg, :phase
end
