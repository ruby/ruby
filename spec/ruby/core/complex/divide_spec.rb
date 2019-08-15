require_relative '../../spec_helper'
require_relative 'shared/divide'

describe "Complex#/" do
  it_behaves_like :complex_divide, :/
end
