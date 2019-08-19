require_relative '../../spec_helper'
require_relative 'shared/eql'

describe "Method#==" do
  it_behaves_like :method_equal, :==
end
