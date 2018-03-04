require_relative '../../spec_helper'
require_relative '../../shared/complex/numeric/imag'

describe "Numeric#imaginary" do
  it_behaves_like :numeric_imag, :imaginary
end
