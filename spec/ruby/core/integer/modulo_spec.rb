require_relative '../../spec_helper'
require_relative 'shared/modulo'

describe "Integer#%" do
  it_behaves_like :integer_modulo, :%
end

describe "Integer#modulo" do
  it_behaves_like :integer_modulo, :modulo
end
