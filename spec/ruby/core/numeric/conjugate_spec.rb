require_relative '../../spec_helper'
require_relative '../../shared/complex/numeric/conj'

describe "Numeric#conjugate" do
  it_behaves_like :numeric_conj, :conjugate
end
