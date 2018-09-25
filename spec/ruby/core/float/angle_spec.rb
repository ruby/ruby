require_relative '../../spec_helper'
require_relative 'shared/arg'

describe "Float#angle" do
  it_behaves_like :float_arg, :angle
end
