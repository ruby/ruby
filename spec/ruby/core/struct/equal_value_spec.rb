require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/equal_value'

describe "Struct#==" do
  it_behaves_like :struct_equal_value, :==
end
