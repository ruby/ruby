require_relative '../../spec_helper'
require_relative 'shared/abs'

describe "Numeric#abs" do
  it_behaves_like :numeric_abs, :abs
end
