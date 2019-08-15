require_relative '../../spec_helper'
require_relative 'shared/abs'

describe "Complex#magnitude" do
  it_behaves_like :complex_abs, :magnitude
end
