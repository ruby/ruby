require_relative '../../spec_helper'
require_relative 'shared/equal'

describe "Proc#eql?" do
  it_behaves_like :proc_equal_undefined, :eql?
end
