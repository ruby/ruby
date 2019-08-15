require_relative '../../spec_helper'
require_relative '../../shared/rational/Rational'

describe "Kernel.Rational" do
  it_behaves_like :kernel_Rational, :Rational
end
