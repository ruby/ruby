require_relative '../../spec_helper'
require_relative 'shared/arg'

describe "Complex#phase" do
  it_behaves_like :complex_arg, :phase
end
