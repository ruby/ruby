require_relative '../../shared/complex/abs'

describe "Complex#magnitude" do
  it_behaves_like :complex_abs, :magnitude
end
