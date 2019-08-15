require_relative '../../spec_helper'
require_relative 'shared/arg'

describe "Float#arg" do
  it_behaves_like :float_arg, :arg
end
