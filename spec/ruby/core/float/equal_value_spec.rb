require_relative '../../spec_helper'
require_relative 'shared/equal'

describe "Float#==" do
  it_behaves_like :float_equal, :==
end
