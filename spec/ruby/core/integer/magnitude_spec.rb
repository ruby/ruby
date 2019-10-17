require_relative '../../spec_helper'
require_relative 'shared/abs'

describe "Integer#magnitude" do
  it_behaves_like :integer_abs, :magnitude
end
