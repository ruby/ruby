require_relative '../../spec_helper'
require_relative 'shared/eql'

describe "Method#eql?" do
  it_behaves_like :method_equal, :eql?
end
