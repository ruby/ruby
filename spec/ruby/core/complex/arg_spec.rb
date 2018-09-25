require_relative '../../spec_helper'
require_relative 'shared/arg'

describe "Complex#arg" do
  it_behaves_like :complex_arg, :arg
end
