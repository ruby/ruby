require_relative '../../spec_helper'
require_relative 'shared/equal'

describe "Integer#===" do
  it_behaves_like :integer_equal, :===
end
