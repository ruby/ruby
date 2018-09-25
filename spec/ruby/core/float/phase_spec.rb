require_relative '../../spec_helper'
require_relative 'shared/arg'

describe "Float#phase" do
  it_behaves_like :float_arg, :phase
end
