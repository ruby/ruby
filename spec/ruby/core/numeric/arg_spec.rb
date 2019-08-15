require_relative '../../spec_helper'
require_relative 'shared/arg'

describe "Numeric#arg" do
  it_behaves_like :numeric_arg, :arg
end
