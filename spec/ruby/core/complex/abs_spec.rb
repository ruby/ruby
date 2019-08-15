require_relative '../../spec_helper'
require_relative 'shared/abs'

describe "Complex#abs" do
  it_behaves_like :complex_abs, :abs
end
