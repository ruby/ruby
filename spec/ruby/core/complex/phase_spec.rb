require_relative '../../spec_helper'
require_relative '../../shared/complex/arg'

describe "Complex#phase" do
  it_behaves_like :complex_arg, :phase
end
