require_relative '../../spec_helper'
require_relative 'shared/abs'

describe "Integer#abs" do
  it_behaves_like :integer_abs, :abs
end
