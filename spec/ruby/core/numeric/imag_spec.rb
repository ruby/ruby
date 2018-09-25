require_relative '../../spec_helper'
require_relative 'shared/imag'

describe "Numeric#imag" do
  it_behaves_like :numeric_imag, :imag
end
