require_relative '../../spec_helper'
require_relative 'shared/abs'

describe "Float#abs" do
  it_behaves_like :float_abs, :abs
end
