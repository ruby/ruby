require_relative '../../spec_helper'
require_relative 'shared/modulo'

describe "Float#%" do
  it_behaves_like :float_modulo, :%
end

describe "Float#modulo" do
  it_behaves_like :float_modulo, :modulo
end
