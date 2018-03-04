require_relative '../../spec_helper'
require_relative '../../shared/complex/Complex'

describe "Kernel.Complex()" do
  it_behaves_like :kernel_Complex, :Complex
end
