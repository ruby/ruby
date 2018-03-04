require_relative '../../spec_helper'
require_relative 'shared/eql'
require_relative 'shared/equal_value'

describe "String#==" do
  it_behaves_like :string_eql_value, :==
  it_behaves_like :string_equal_value, :==
end
